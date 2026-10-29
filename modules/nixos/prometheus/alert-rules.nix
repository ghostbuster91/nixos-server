{ lib }:
let
  # Percent of capacity used, as one series per ZFS pool on the hosts that run
  # the zfs exporter (beast: rpool1 + dpool, malina5: rpool1) and one series per
  # host everywhere else, labelled pool="all filesystems". Shared by the two
  # disk_space_* alerts below so the expression is written once; it is the same
  # expression the "Disk space" dashboard uses per host.
  #
  # The filesystem branch covers the hosts without the exporter: thunder
  # (ZFS-rooted, but only `nixosModules.zfs` enables the exporter and thunder
  # doesn't import it) and surfer (ext4 on eMMC).
  #
  # - `max by (host, device)` collapses the many mountpoints that share one
  #   device -- /nix and /nix/store, or every bind mount off rpool1/safe/persist
  #   -- into one series, so the sum counts each device exactly once.
  # - the denominator is used + `max` avail, not a sum of per-mountpoint sizes:
  #   on a ZFS host every dataset reports the pool's remaining space as `avail`,
  #   so summing sizes would count the free space once per dataset. Taking it
  #   once reconstructs pool capacity.
  # - tmpfs/ramfs are excluded (/run, /run/keys -- ephemeral, not disk).
  # - `unless on(host)` drops the filesystem branch for any host the zfs
  #   exporter already covers, so pool-level numbers are never mixed with
  #   dataset-level ones for the same host.
  #
  # Aggregating the zfs branch with `sum by (host, pool)` is not about summing
  # (there is exactly one series per pool) -- it strips `instance`/`job` so both
  # branches carry the same {host, pool} label set.
  diskFsFilter = ''{fstype!~"tmpfs|ramfs"}'';
  diskFsUsed = ''sum by (host) (max by (host, device) (node_filesystem_size_bytes${diskFsFilter} - node_filesystem_avail_bytes${diskFsFilter}))'';
  diskFsAvail = ''max by (host) (node_filesystem_avail_bytes${diskFsFilter})'';
  # Parenthesised: `>` binds tighter than `or`/`unless` in PromQL, so without
  # the parens a threshold appended by the caller would apply to the last
  # operand only.
  diskUsedPercent = ''
    (
      100 * sum by (host, pool) (zfs_pool_allocated_bytes) / sum by (host, pool) (zfs_pool_size_bytes)
      or
      label_replace(100 * ${diskFsUsed} / (${diskFsUsed} + ${diskFsAvail}), "pool", "all filesystems", "", "")
        unless on(host) zfs_pool_size_bytes
    )'';
in
lib.mapAttrsToList
  (name: opts: # Params
  {
    alert = name;
    expr = opts.condition;
    for = opts.time or "2m";
    # Every alert carries a severity: it picks the ntfy priority (`critical`
    # becomes an `urgent` push, which overrides the phone's do-not-disturb) and
    # it drives the critical -> warning inhibit rule -- see
    # prometheus/server.nix. Rules default to `warning` and opt up with
    # `severity = "critical"`.
    labels.severity = opts.severity or "warning";
    annotations = {
      # alertmanager-ntfy renders `summary` as the push title; default it to the
      # alert name so a rule that doesn't set one still gets a usable title.
      summary = opts.summary or name;
      description = opts.description;
    };
  }
  )
  (
    {
      # Originally from badele/nix-homelab. `flake_input_last_modified` had no
      # producer in this repo, so this never fired; prometheus/client.nix now
      # renders it from the flake lock into node_exporter's textfile collector.
      # The old `host!="matchbox"` filter named a machine that is not in this
      # fleet, so it is gone.
      nixpkgs_out_of_date = {
        condition = ''(time() - flake_input_last_modified{input="nixpkgs"}) / (60*60*24) > 60'';
        description = "{{$labels.host}}: nixpkgs flake input is more than 60 days old";
      };

      # The systemd exporter emits `systemd_unit_state{name,state,type}`, not
      # the `systemd_units_active_code` this used to query -- that metric does
      # not exist, so this alert was dead. user@<uid>.service is excluded
      # because it fails routinely and harmlessly on session teardown.
      #
      # The regex needs doubled backslashes: this `''`-string keeps them
      # literal, builtins.toJSON escapes them again, and PromQL then unescapes
      # the string literal back to `\d` / `\.`. A single backslash here fails
      # `promtool check rules` with "unknown escape sequence".
      systemd_service_failed = {
        condition = ''systemd_unit_state{state="failed", name!~"user@\\d+\\.service"} == 1'';
        description = "{{$labels.host}}: unit {{$labels.name}} has failed";
      };

      # --- Disk space ---------------------------------------------------------
      # Two tiers over the same `diskUsedPercent` expression. The 80% tier rides
      # the default `warning` severity (an ordinary ntfy push); the 90% tier is
      # `critical` (an `urgent` push) and mutes the 80% one for the same pool
      # while it fires -- see inhibit_rules in prometheus/server.nix.
      disk_space_high = {
        condition = ''${diskUsedPercent} > 80'';
        # Pools fill over days, so a long `for` costs nothing and rides out the
        # transient spikes that do exist: a big nix build before GC, a borg run,
        # a large paperless/comfyui import.
        time = "30m";
        summary = "Disk {{ $value | printf \"%.0f\" }}% full on {{$labels.host}}";
        description = ''{{$labels.host}} {{$labels.pool}}: {{ $value | printf "%.1f" }}% of capacity used -- free space or prune snapshots. ZFS also starts to fragment and slow down past 80%.'';
      };

      disk_space_critical = {
        condition = ''${diskUsedPercent} > 90'';
        # Shorter than the warning tier: past 90% there is little headroom left,
        # so trading a bit of noise for earlier notice is the right way round.
        time = "10m";
        severity = "critical";
        summary = "Disk {{ $value | printf \"%.0f\" }}% FULL on {{$labels.host}}";
        description = ''{{$labels.host}} {{$labels.pool}}: {{ $value | printf "%.1f" }}% of capacity used -- act now. A full pool fails writes, wedges services and leaves no room for snapshots or a rollback.'';
      };

      # SMART/NVMe health. `host` comes from the smartctl job's static_configs
      # labels (beast or malina5); `device` is nvme0/nvme1. The "Disk health
      # (SMART)" dashboard maps those pairs to models and serials.
      disk_smart_failed = {
        condition = ''smartctl_device_smart_status == 0'';
        description = "{{$labels.host}} {{$labels.device}}: SMART self-assessment FAILED -- replace this disk";
      };

      disk_nvme_critical_warning = {
        condition = ''smartctl_device_critical_warning > 0'';
        description = "{{$labels.host}} {{$labels.device}}: NVMe critical warning bitfield is {{$value}} (spare low / temperature / degraded reliability / read-only / backup failed)";
      };

      disk_media_errors = {
        condition = ''increase(smartctl_device_media_errors[1h]) > 0'';
        description = "{{$labels.host}} {{$labels.device}}: unrecovered data integrity errors increased in the last hour (now {{$value}})";
      };

      # Spare blocks are reported as a percentage alongside the manufacturer's
      # own threshold (10% on these Samsungs), so compare the two rather than
      # hardcoding a number.
      disk_spare_below_threshold = {
        condition = ''smartctl_device_available_spare <= smartctl_device_available_spare_threshold'';
        description = "{{$labels.host}} {{$labels.device}}: available spare NAND at {{$value}}%, at or below the manufacturer threshold";
      };

      disk_wear_high = {
        condition = ''smartctl_device_percentage_used >= 80'';
        # Wear only ever climbs, so there is no point re-checking for minutes.
        time = "0m";
        description = "{{$labels.host}} {{$labels.device}}: {{$value}}% of rated write endurance consumed -- plan a replacement";
      };

      disk_temperature_high = {
        condition = ''smartctl_device_temperature{temperature_type="current"} > 70'';
        time = "10m";
        description = "{{$labels.host}} {{$labels.device}}: NVMe at {{$value}}C for 10m -- throttling starts near 78C";
      };

      # Every smartctl target crosses the tailnet, so a dead one is a real (and
      # silent) failure mode: no metrics means no disk alerts at all.
      disk_exporter_down = {
        condition = ''up{job="smartctl"} == 0'';
        time = "15m";
        description = "{{$labels.host}}: smartctl exporter unreachable for 15m -- SMART alerts for its disks are blind";
      };
    })
