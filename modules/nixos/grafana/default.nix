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
  age.secrets.grafana-secret-key = {
    file = ../../../secrets/grafana-secret-key.age;
    mode = "440";
    group = "grafana";
  };

  # Mirror the original oauth2 secret
  age.secrets.grafana-oauth2-client-secret = {
    inherit (config.age.secrets.kanidm-oauth2-grafana) file;
    mode = "440";
    group = "grafana";
  };

  environment.persistence."/persist".directories = [
    {
      directory = config.services.grafana.dataDir;
      user = "grafana";
      group = "grafana";
      mode = "0700";
    }
  ];
  # options = with lib; {
  #   homelab.domain = mkOption {
  #     type = types.str;
  #   };
  # };
  # grafana configuration
  systemd.services.nginx = {
    requires = [ "grafana.service" ];
  };
  services = {
    grafana = {
      enable = true;

      settings = {
        analytics.reporting_enabled = false;

        server = {
          domain = "${roleName}.${config.homelab.ext-domain}";
          addr = "127.0.0.1";
          root_url = "https://${roleName}.${config.homelab.ext-domain}";
        };
        security = {
          disable_initial_admin_creation = true;
          secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";
          cookie_secure = true;
          disable_gravatar = true;
          hide_version = true;
        };

        auth.disable_login_form = true;
        "auth.generic_oauth" = {
          enabled = true;
          name = "Kanidm";
          icon = "signin";
          allow_sign_up = true;
          #auto_login = true;
          client_id = "grafana";
          client_secret = "$__file{${config.age.secrets.grafana-oauth2-client-secret.path}}";
          scopes = "openid email profile";
          login_attribute_path = "preferred_username";
          auth_url = "https://auth.${config.homelab.ext-domain}/ui/oauth2";
          token_url = "https://auth.${config.homelab.ext-domain}/oauth2/token";
          api_url = "https://auth.${config.homelab.ext-domain}/oauth2/openid/grafana/userinfo";
          use_pkce = true;
          # Allow mapping oauth2 roles to server admin
          allow_assign_grafana_admin = true;
          role_attribute_path = "contains(groups[*], 'server_admin') && 'GrafanaAdmin' || contains(groups[*], 'admin') && 'Admin' || contains(groups[*], 'editor') && 'Editor' || 'Viewer'";
        };
      };
      provision = {
        enable = true;

        datasources.settings.datasources = [
          {
            uuid = "PBFA97CFB590B2093";
            name = "Prometheus";
            type = "prometheus";
            access = "proxy";
            url = "http://localhost:${toString config.services.prometheus.port}";
            ## https://github.com/rfmoz/grafana-dashboards/issues/169
            jsonData = {
              timeInterval = (builtins.elemAt config.services.prometheus.scrapeConfigs 0).scrape_interval;
            };
          }
          {
            uuid = "P8E80F9AEF21F6940";
            name = "Loki";
            type = "loki";
            access = "proxy";
            url = "http://localhost:${toString config.services.loki.configuration.server.http_listen_port}";
          }
        ];

        dashboards.settings.providers = [{
          name = "default";
          options.path = grafana-dashboards;
        }];
      };
    };

    # nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
    #   # serverName = "${roleName}.${config.homelab.domain}";
    #   sslCertificate = config.age.secrets."nginx-selfsigned.cert".path;
    #   sslCertificateKey = config.age.secrets."nginx-selfsigned.key".path;
    #   forceSSL = true;
    #
    #   locations."/" = {
    #     proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
    #     proxyWebsockets = true;
    #     recommendedProxySettings = true;
    #   };
    # };
    nginx.virtualHosts."${roleName}.${config.homelab.ext-domain}" = {
      # Use wildcard domain
      useACMEHost = config.homelab.ext-domain;
      # serverName = "${roleName}.${config.homelab.ext-domain}";
      # sslCertificate = config.age.secrets."nginx-selfsigned.cert".path;
      # sslCertificateKey = config.age.secrets."nginx-selfsigned.key".path;
      forceSSL = true;
      # serverAliases = [ "${roleName}.${config.homelab.ext-domain}" ];

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.grafana.settings.server.http_port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
