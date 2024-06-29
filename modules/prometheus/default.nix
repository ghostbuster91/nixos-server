{ config, pkgs, ... }:
let
  roleName = "prometheus";
  cfg = config.services.prometheus;
in
{
  services.prometheus = {
    enable = true;
    port = 9001;
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [ "systemd" ];
        port = 9002;
      };
    };
    # webExternalUrl="http://deckard.lan/prometheus/";
    scrapeConfigs = [
      {
        job_name = "deckard";
        static_configs = [{
          targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
      {
        job_name = "surfer";
        static_configs = [{
          targets = [ "192.168.10.1:${toString config.services.prometheus.exporters.node.port}" ];
        }];
      }
    ];
  };

  services.nginx.enable = true;
  services.nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
    # Use wildcard domain
    # useACMEHost = config.homelab.domain;
    forceSSL = false;
    serverName = "prometheus.deckard.lan";
    locations."/" = {
      extraConfig = ''
        proxy_pass http://127.0.0.1:${toString cfg.port};
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;      
      '';
    };
  };
}
