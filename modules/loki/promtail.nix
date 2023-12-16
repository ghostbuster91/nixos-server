{ lib, config, ... }:
let
  roleName = "loki";
  port_promtail = 3031;
in
{

  networking.firewall.allowedTCPPorts = [
    port_promtail
  ];

  services.promtail = {
    enable = true;
    configuration = {
      server = {
        # http_listen_port = port_promtail;
        disable=true;
      };
      # positions = {
      #   filename = "/var/log/positions.yaml";
      # };
      clients = [{
        url = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}/loki/api/v1/push";
      }];
      scrape_configs = [{
        job_name = "journal";
        journal = {
          max_age = "12h";
          labels = {
            job = "systemd-journal";
            host = "deckard";
          };
        };
        relabel_configs = [{
          source_labels = [ "__journal__systemd_unit" ];
          target_label = "unit";
        }];
      }];
    };
  };

  services.nginx.enable = true;
  services.nginx.virtualHosts."promtail.${config.homelab.domain}" = {
    # Use wildcard domain
    # useACMEHost = config.homelab.domain;
    serverName= "promtail.deckard.lan";
    forceSSL = false;

    locations."/" = {
      extraConfig = ''
        proxy_pass http://127.0.0.1:${toString port_promtail};
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;      
      '';
    };
  };

}
