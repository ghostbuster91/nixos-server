{ config, pkgs, lib, ... }:
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
  age.secrets."alertmanager" = {
    file = ../../../secrets/alertmanager.age;
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

      # Test alertmanager
      # curl -H 'Content-Type: application/json' -d '[{"labels":{"alertname":"myalert"}}]' http://127.0.0.1:9093/api/v2/alerts
      alertmanagers = [
        {
          scheme = "http";
          path_prefix = "/";
          static_configs = [{ targets = [ "127.0.0.1:${toString config.services.prometheus.alertmanager.port}" ]; }];
        }
      ];

      # alertmanager might fail to start if impermanence mounts esphome directory first. In this case disable temporary esphome mount and restart alertmanager
      alertmanager = {
        enable = true;
        logLevel = "debug";

        # Secret content all variables content
        # example:
        # alertmanager: |
        #  var_name1=value1
        #  var_name2=value2
        environmentFile = config.age.secrets.alertmanager.path;
        extraFlags = [
          "--cluster.listen-address=" # disables HA mode
        ];
        configuration = {
          receivers = [
            {
              name = "pushover";
              pushover_configs = [
                {
                  send_resolved = true;
                  user_key = "$PUSHOVER_USER_KEY";
                  token = "$PUSHOVER_TOKEN";
                }
              ];
            }
          ];

          route = {
            receiver = "pushover";
            routes = [
              {
                group_wait = "30s";
                group_interval = "2m";
                repeat_interval = "4h";
                group_by = [ "alertname" "alias" ];
                receiver = "pushover";
              }
            ];
          };
        };
      };

      ruleFiles = [
        (pkgs.writeText "prometheus-rules.yml" (
          builtins.toJSON {
            groups = [
              {
                name = "alerting-rules";
                rules = import ./alert-rules.nix { inherit lib; };
              }
            ];
          }
        ))
      ];


      scrapeConfigs = let scrape_interval = "60s"; in [
        {
          job_name = "node_exporter";
          inherit scrape_interval;
          static_configs = [{
            targets = [
              "deckard.${config.homelab.domain}:${toString config.services.prometheus.exporters.node.port}"
              "surfer.${config.homelab.domain}:${toString config.services.prometheus.exporters.node.port}"
              "malina5.${config.homelab.domain}:${toString config.services.prometheus.exporters.node.port}"
            ];
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
          job_name = "zfs";
          inherit scrape_interval;
          static_configs = [{
            targets = [ "deckard.${config.homelab.domain}:${toString config.services.prometheus.exporters.zfs.port}" ];
          }];
        }
        {
          job_name = "systemd";
          inherit scrape_interval;
          static_configs = [{
            targets = [ "deckard.${config.homelab.domain}:${toString config.services.prometheus.exporters.systemd.port}" ];
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
