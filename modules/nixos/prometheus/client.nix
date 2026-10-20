{ config, inputs, lib, pkgs, ... }:
let
  # Producer for `flake_input_last_modified`, which the `nixpkgs_out_of_date`
  # alert consumes. Nothing emitted it before, so that rule could never fire.
  #
  # The values come from the flake lock at eval time, so the file is immutable
  # for the lifetime of a generation -- point the textfile collector straight at
  # a store directory instead of maintaining a writable one. (A metric that has
  # to be refreshed at runtime would need a real directory plus a timer.)
  #
  # Deliberately no `host` label here: the scrape job attaches one as a target
  # label, and an exposed label of the same name would be renamed to
  # `exported_host` rather than merged.
  flakeInputMetrics = pkgs.writeTextDir "flake-inputs.prom" (''
    # HELP flake_input_last_modified Unix timestamp of a flake input's last modification, from flake.lock.
    # TYPE flake_input_last_modified gauge
  '' + lib.concatStrings (lib.mapAttrsToList
    (name: input:
      lib.optionalString (input ? lastModified)
        "flake_input_last_modified{input=\"${name}\"} ${toString input.lastModified}\n")
    inputs));
in
{

  networking.firewall = {
    interfaces."tailscale0" = {
      allowedTCPPorts = [
        config.services.prometheus.exporters.node.port
        config.services.prometheus.exporters.systemd.port
      ];
    };
  };
  services.prometheus = {
    exporters = {
      # openFirewall is deliberately off: it renders an *unscoped*
      # `ip46tables -A nixos-fw -p tcp --dport <port>` (via extraCommands, not
      # allowedTCPPorts), which accepts on every interface including the LAN --
      # and node_exporter exposes a lot about a host. The interface-scoped rules
      # above are what we actually want, and they cover every scrape path:
      # remote targets arrive on tailscale0, and a host scraping its own
      # `<host>.tail.<domain>` routes to a local address via `lo`, which
      # nixos-fw accepts unconditionally.
      node = {
        enable = true;
        openFirewall = false;
        port = 9002;
        # `textfile` is in node_exporter's default collector set; it only needs
        # pointing at a directory of *.prom files.
        extraFlags = [ "--collector.textfile.directory=${flakeInputMetrics}" ];
      };
      systemd = {
        enable = true;
        port = 9003;
        openFirewall = false;
      };
    };
  };

}
