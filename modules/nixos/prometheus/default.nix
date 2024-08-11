{ config, ... }:
let
  roleName = "prometheus";
  cfg = config.services.prometheus;
in
{
  # options = with lib; {
  #   homelab.domain = mkOption {
  #     type = types.str;
  #   };
  # };
  systemd.services.nginx = {
    serviceConfig.SupplementaryGroups = [ "prometheus" ];
    requires = [ "prometheus.service" ];
  };
  services = {
    prometheus = {
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

    nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
      # Use wildcard domain
      # useACMEHost = config.homelab.domain;
      forceSSL = false;
      serverName = "${roleName}.${config.homelab.domain}";
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
