{ config, pkgs, ... }:
let
  roleName = "grafana";
  grafana-dashboards = pkgs.stdenv.mkDerivation {
    name = "grafana-dashboards";
    src = ./.;
    installPhase = ''
      mkdir -p $out/
      install -D -m755 $src/dashboards/*.json $out/
    '';
  };
in
{
  # grafana configuration
  networking.firewall.allowedTCPPorts = [
    # config.services.grafana.settings.server.http_port
    80
    443
  ];
  services = {
    grafana = {
      enable = true;

      settings = {
        analytics.reporting_enabled = false;

        server = {
          domain = "${roleName}.${config.homelab.domain}";
          addr = "127.0.0.1";
        };
      };

      provision.datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:${toString config.services.prometheus.port}";
        }
        {
          name = "Loki";
          type = "loki";
          access = "proxy";
          url = "http://127.0.0.1:${toString config.services.loki.configuration.server.http_listen_port}";
        }
      ];

      provision.dashboards.settings.providers = [{
        name = "default";
        options.path = grafana-dashboards;
      }];
    };

    nginx.enable = true;
    nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
      # Use wildcard domain
      # useACMEHost = config.homelab.domain;
      serverName = "${roleName}.${config.homelab.domain}";
      forceSSL = false;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
