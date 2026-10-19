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
      # from https://sourcegraph.com/github.com/badele/nix-homelab/-/blob/nix/nixos/roles/prometheus/default.nix?L44=
      nixpkgs_out_of_date = {
        condition = ''(time() - flake_input_last_modified{input="nixpkgs",host!="matchbox"}) / (60*60*24) > 7'';
        description = "{{$labels.host}}: nixpkgs flake is older than a week";
      };

      # user@$uid.service and similar sometimes fail, we don't care about those services.
      # nixpkgs-update also constantly fails and ryan does not fix it.
      systemd_service_failed = {
        condition = ''systemd_units_active_code{name!~"user@\\d+.service|nixpkgs-update.*"} == 3'';
        description = "{{$labels.host}} failed to (re)start service {{$labels.name}}";
      };

      service_not_running = {
        condition = ''systemd_units_active_code{name=~"teamspeak3-server.service|tt-rss.service", sub!="running"}'';
        description = "{{$labels.host}} should have a running {{$labels.name}}";
      };

      # SMART/NVMe health for beast's two NVMe SSDs. The exporter only runs on
      # beast (hosts/x86_64-linux/beast/smartctl.nix), so these carry no host
      # label — `device` is nvme0 (rpool1) or nvme1 (dpool); the "Disk health
      # (SMART)" dashboard maps those to models and serials.
      disk_smart_failed = {
        condition = ''smartctl_device_smart_status == 0'';
        description = "beast {{$labels.device}}: SMART self-assessment FAILED -- replace this disk";
      };

      disk_nvme_critical_warning = {
        condition = ''smartctl_device_critical_warning > 0'';
        description = "beast {{$labels.device}}: NVMe critical warning bitfield is {{$value}} (spare low / temperature / degraded reliability / read-only / backup failed)";
      };

      disk_media_errors = {
        condition = ''increase(smartctl_device_media_errors[1h]) > 0'';
        description = "beast {{$labels.device}}: unrecovered data integrity errors increased in the last hour (now {{$value}})";
      };

      # Spare blocks are reported as a percentage alongside the manufacturer's
      # own threshold (10% on these Samsungs), so compare the two rather than
      # hardcoding a number.
      disk_spare_below_threshold = {
        condition = ''smartctl_device_available_spare <= smartctl_device_available_spare_threshold'';
        description = "beast {{$labels.device}}: available spare NAND at {{$value}}%, at or below the manufacturer threshold";
      };

      disk_wear_high = {
        condition = ''smartctl_device_percentage_used >= 80'';
        # Wear only ever climbs, so there is no point re-checking for minutes.
        time = "0m";
        description = "beast {{$labels.device}}: {{$value}}% of rated write endurance consumed -- plan a replacement";
      };

      disk_temperature_high = {
        condition = ''smartctl_device_temperature{temperature_type="current"} > 70'';
        time = "10m";
        description = "beast {{$labels.device}}: NVMe at {{$value}}C for 10m -- throttling starts near 78C";
      };
    })
