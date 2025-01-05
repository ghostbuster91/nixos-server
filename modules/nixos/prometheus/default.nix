{ config, ... }:
let
  roleName = "prometheus";
  cfg = config.services.prometheus;
in
{
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/${config.services.prometheus.stateDir}";
      user = "prometheus";
      group = "prometheus";
      mode = "0700";
    }
  ];
  age.secrets."prometheus-hass-token" = {
    file = ../../../secrets/prometheus-hass-token.age;
    mode = "440";
    owner = "prometheus";
    group = "prometheus";
  };
  systemd.services.nginx = {
    requires = [ "prometheus.service" ];
  };
  services = {
    prometheus = {
      enable = true;
      port = 9001;

      # By default the check verifies also if all referenced paths exist.
      # This however cannot work if any of these paths refers to age/sops secrets as these files are created during the activation phase.
      checkConfig = "syntax-only";

      exporters = {
        node = {
          enable = true;
          enabledCollectors = [ "systemd" ];
          port = 9002;
        };
      };
      scrapeConfigs = let scrape_interval = "60s"; in [
        {
          job_name = "deckard";
          inherit scrape_interval;
          static_configs = [{
            targets = [ "127.0.0.1:${ toString config. services. prometheus. exporters. node. port}" ];
          }];
        }
        {
          job_name = "haas";
          metrics_path = "/api/prometheus";
          inherit scrape_interval;
          # Long-Lived Access Token
          authorization. credentials_file = config.age.secrets."prometheus-hass-token".path;
          static_configs = [{
            targets = [ "localhost:${toString config.services.home-assistant.config.http.server_port}" ];
          }];
        }
        {
          job_name = "surfer";
          inherit scrape_interval;
          static_configs = [{
            targets = [ "192.168.10.1:${toString config.services.prometheus.exporters.node.port}" ];
          }];
        }
      ];
    };

    nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
      # Use wildcard domain
      # useACMEHost = config.homelab.domain;
      serverName = "${roleName}.${config.homelab.domain}";

      sslCertificate = config.age.secrets."nginx-selfsigned.cert".path;
      sslCertificateKey = config.age.secrets."nginx-selfsigned.key".path;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
