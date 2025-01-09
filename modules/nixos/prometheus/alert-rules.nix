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
    })
