{ config, pkgs, ... }:
let
  # Shared with monitoring.nix: node_exporter's textfile collector reads *.prom
  # from here, so dropping funbox.prom / funbox-health.prom in is enough -- no
  # extra scrape job or port. The tmpfiles rule that creates the dir lives in
  # monitoring.nix.
  textfileDir = "/run/node-exporter-textfile";
in
{
  # Admin creds for the SAH createContext login, as an EnvironmentFile:
  #   FUNBOX_USER=admin
  #   FUNBOX_PASSWORD=...
  age.secrets."funbox-admin".file = ../../../secrets/funbox-admin.age;

  systemd.services.funbox-metrics = {
    description = "Collect Orange FunBox topology device metrics for node_exporter";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${./funbox-exporter.py}";
      EnvironmentFile = config.age.secrets."funbox-admin".path;
      Environment = [
        "FUNBOX_URL=http://192.168.1.1/ws"
        "TEXTFILE_DIR=${textfileDir}"
      ];
      # Hardening: no privileges needed, only the textfile dir is written.
      DynamicUser = false;
      ProtectSystem = "strict";
      ReadWritePaths = [ textfileDir ];
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
    };
  };

  systemd.timers.funbox-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "60s";
      AccuracySec = "10s";
    };
  };
}
