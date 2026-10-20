{ lib }:
lib.mapAttrsToList
  (name: opts: # Params
  {
    alert = name;
    expr = opts.condition;
    for = opts.time or "2m";
    labels = { };
    annotations.description = opts.description;
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
