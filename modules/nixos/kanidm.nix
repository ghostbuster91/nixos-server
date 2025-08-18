{ pkgs, config, ... }:
let
  kanidmDomainExt = "auth.${config.homelab.ext-domain}";
  kanidmPort = 8300;
  mkSecret = file: {
    inherit file;
    mode = "440";
    group = "kanidm";
  };
in
{
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/kanidm";
      user = "kanidm";
      group = "kanidm";
      mode = "0700";
    }
  ];

  age.secrets.kanidm-admin-password = mkSecret ../../secrets/kanidm-admin-password.age;
  age.secrets.kanidm-idm-admin-password = mkSecret ../../secrets/kanidm-idm-admin-password.age;
  age.secrets.kanidm-oauth2-grafana = mkSecret ../../secrets/kanidm-oauth2-grafana.age;

  age.secrets."kanidm-selfsigned.cert" = {
    file = ../../secrets/kanidm-selfsigned.cert.age;
    mode = "440";
    owner = "kanidm";
    group = "kanidm";
  };

  age.secrets."kanidm-selfsigned.key" = {
    file = ../../secrets/kanidm-selfsigned.key.age;
    mode = "440";
    owner = "kanidm";
    group = "kanidm";
  };

  services.kanidm = {
    package = pkgs.kanidm.withSecretProvisioning;
    enableServer = true;
    serverSettings = {
      origin = "https://${kanidmDomainExt}";
      domain = config.homelab.ext-domain;
      tls_chain = config.age.secrets."kanidm-selfsigned.cert".path;
      tls_key = config.age.secrets."kanidm-selfsigned.key".path;
      bindaddress = "127.0.0.1:${toString kanidmPort}";
      trust_x_forward_for = true;
    };

    enableClient = true;
    clientSettings = {
      uri = config.services.kanidm.serverSettings.origin;
      verify_ca = true;
      verify_hostnames = true;
    };

    provision = {
      enable = true;
      persons = {
        "kasper" = {
          mailAddresses = [ "noreply@example.com" ];
          groups = [ "grafana.admins" "grafana.server-admins" "grafana.access" ];
          displayName = "Kasper";
        };
      };
      # Grafana
      groups."grafana.access" = { };
      groups."grafana.editors" = { };
      groups."grafana.admins" = { };
      groups."grafana.server-admins" = { };
      systems.oauth2.grafana = {
        displayName = "Grafana";
        originUrl = "https://grafana.${config.homelab.ext-domain}/login/generic_oauth";
        originLanding = "https://grafana.${config.homelab.ext-domain}/";
        basicSecretFile = config.age.secrets.kanidm-oauth2-grafana.path;
        preferShortUsername = true;
        scopeMaps."grafana.access" = [
          "openid"
          "email"
          "profile"
        ];
        claimMaps.groups = {
          joinType = "array";
          valuesByGroup = {
            "grafana.editors" = [ "editor" ];
            "grafana.admins" = [ "admin" ];
            "grafana.server-admins" = [ "server_admin" ];
          };
        };
      };
    };
  };
  services.nginx = {
    upstreams.kanidm = {
      servers."127.0.0.1:${toString kanidmPort}" = { };
      extraConfig = ''
        zone kanidm 64k;
        keepalive 2;
      '';
    };
    virtualHosts."auth.${config.homelab.ext-domain}" = {
      forceSSL = true;
      useACMEHost = config.homelab.ext-domain;
      locations."/" = {
        proxyPass = "https://kanidm";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
      # Allow using self-signed certs to satisfy kanidm's requirement
      # for TLS connections. (Although this is over wireguard anyway)
      extraConfig = ''
        proxy_ssl_verify off;
      '';
    };
  };
}
