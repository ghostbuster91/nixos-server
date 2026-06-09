{ config, lib, pkgs, ... }:
let
  cfg = config.services.attic-watch-store;
in
{
  options.services.attic-watch-store = {
    enable = lib.mkEnableOption "attic watch-store auto-pusher";

    cache = lib.mkOption {
      type = lib.types.str;
      example = "malina5:system";
      description = "Target cache in the form <server>:<cache>.";
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
      after = [ "network-online.target" "nix-daemon.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        Restart = "on-failure";
        RestartSec = 10;

        DynamicUser = true;
        RuntimeDirectory = "attic-watch-store";
        LoadCredential = "config.toml:${cfg.credentialsFile}";

        ExecStartPre = pkgs.writeShellScript "attic-watch-store-setup" ''
          set -euo pipefail
          install -d -m 700 "$RUNTIME_DIRECTORY/attic"
          install -m 600 "$CREDENTIALS_DIRECTORY/config.toml" "$RUNTIME_DIRECTORY/attic/config.toml"
        '';

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
