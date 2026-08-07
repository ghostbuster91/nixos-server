{ config, lib, pkgs, ... }:
let
  cfg = config.services.attic-watch-store;

  # Optional gate: block startup until the cache endpoint resolves. The attic
  # endpoint is served over thunder's VPN-only MagicDNS, which can be briefly
  # unavailable during a deploy while networking reconverges. attic exits
  # non-zero on a transient lookup miss (it queries cache-config once before
  # watching), which would mark the unit failed and trip deploy-rs autoRollback.
  waitForDns = import ./lib/wait-for-dns.nix { inherit pkgs lib; };

  setup = pkgs.writeShellScript "attic-watch-store-setup" ''
    set -euo pipefail
    install -d -m 700 "$RUNTIME_DIRECTORY/attic"
    install -m 600 "$CREDENTIALS_DIRECTORY/config.toml" "$RUNTIME_DIRECTORY/attic/config.toml"
  '';
in
{
  options.services.attic-watch-store = {
    enable = lib.mkEnableOption "attic watch-store auto-pusher";

    cache = lib.mkOption {
      type = lib.types.str;
      example = "malina5:system";
      description = "Target cache in the form <server>:<cache>.";
    };

    waitForHost = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "attic.example.com";
      description = ''
        Optional hostname to wait for (DNS resolution) before starting. Set this
        to the cache endpoint host when it is served over a VPN-only resolver
        that may lag behind a deploy, so a transient lookup miss cannot fail
        activation.
      '';
    };

    afterLocalNginx = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Order this unit after nginx.service. Set this when the cache endpoint is
        reverse-proxied by *this host's own* nginx: a switch-to-configuration
        restarts nginx, and if attic-watch-store is (re)started into that window
        the local connection is refused (TCP), the unit fails, and deploy-rs
        autoRollback reverts the generation. Ordering after nginx closes that
        window. Leave false when the cache is served by another host.
      '';
    };

    credentialsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to a complete attic config.toml containing the server endpoint
        and a push-capable token. Typically an agenix-managed secret.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.attic-watch-store = {
      description = "Push new store paths to attic cache";
      # tailscaled brings up the tailnet that MagicDNS resolves through; order
      # after it so the DNS gate isn't fighting the daemon's own startup.
      after = [ "network-online.target" "nix-daemon.service" "tailscaled.service" ]
        ++ lib.optional cfg.afterLocalNginx "nginx.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 10;

        DynamicUser = true;
        RuntimeDirectory = "attic-watch-store";
        LoadCredential = "config.toml:${cfg.credentialsFile}";

        ExecStartPre =
          lib.optional (cfg.waitForHost != null) (waitForDns cfg.waitForHost)
          ++ [ setup ];

        ExecStart = "${pkgs.attic-client}/bin/attic watch-store ${lib.escapeShellArg cfg.cache}";

        Environment = [ "XDG_CONFIG_HOME=%t/attic-watch-store" ];

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };
}
