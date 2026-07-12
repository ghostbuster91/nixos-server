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
  age.secrets.kanidm-oauth2-proxy = mkSecret ../../secrets/kanidm-oauth2-proxy.age;
  age.secrets.kanidm-oauth2-linkwarden = mkSecret ../../secrets/kanidm-oauth2-linkwarden.age;
  age.secrets.kanidm-oauth2-actual = mkSecret ../../secrets/kanidm-oauth2-actual.age;
  age.secrets.kanidm-oauth2-mealie = mkSecret ../../secrets/kanidm-oauth2-mealie.age;

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
    package = pkgs.kanidmWithSecretProvisioning_1_9;
    enableServer = true;
    serverSettings = {
      origin = "https://${kanidmDomainExt}";
      domain = config.homelab.ext-domain;
      tls_chain = config.age.secrets."kanidm-selfsigned.cert".path;
      tls_key = config.age.secrets."kanidm-selfsigned.key".path;
      bindaddress = "127.0.0.1:${toString kanidmPort}";
      # kanidm config v2 replaced the `trust_x_forward_for` boolean with the
      # `http_client_address_info` enum. kanidm binds loopback and is only
      # reached by the local nginx reverse proxy, so trust X-Forwarded-For from
      # 127.0.0.1 (the proxy) to keep seeing the real client IP.
      http_client_address_info = {
        "x-forward-for" = [ "127.0.0.1/32" ];
      };
    };

    enableClient = true;
    clientSettings = {
      uri = config.services.kanidm.serverSettings.origin;
      verify_ca = true;
      verify_hostnames = true;
    };

    provision = {
      enable = true;
      persons =
        let
          familyGroups = [ "web-sentinel.access" "web-sentinel.openwebui" "mealie.access" "ha.access" ];
        in
        {
          "kasper" = {
            mailAddresses = [ "kasper.noreply@example.com" ];
            groups = [ "grafana.admins" "grafana.server-admins" "grafana.access" "web-sentinel.access" "web-sentinel.openwebui" "linkwarden.access" "actual.access" "mealie.access" "mealie.admins" "ha.access" "ha.admins" ];
            displayName = "Kasper";
          };
          "kamil" = {
            mailAddresses = [ "kamil.noreply@example.com" ];
            groups = familyGroups;
            displayName = "Kamil";
          };
          "kornel" = {
            mailAddresses = [ "kornel.noreply@example.com" ];
            groups = familyGroups;
            displayName = "Kornel";
          };
          "marta" = {
            mailAddresses = [ "marta.noreply@example.com" ];
            groups = familyGroups;
            displayName = "Marta";
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
      # Web Sentinel
      groups."web-sentinel.access" = { };
      groups."web-sentinel.adguardhome" = { };
      groups."web-sentinel.openwebui" = { };
      groups."web-sentinel.analytics" = { };
      systems.oauth2.web-sentinel = {
        displayName = "Web Sentinel";
        originUrl = "https://oauth2.${config.homelab.ext-domain}/oauth2/callback";
        originLanding = "https://oauth2.${config.homelab.ext-domain}/";
        basicSecretFile = config.age.secrets.kanidm-oauth2-proxy.path;
        preferShortUsername = true;
        scopeMaps."web-sentinel.access" = [
          "openid"
          "email"
        ];
        claimMaps.groups = {
          joinType = "array";
          valuesByGroup."web-sentinel.adguardhome" = [ "access_adguardhome" ];
          valuesByGroup."web-sentinel.openwebui" = [ "access_openwebui" ];
          valuesByGroup."web-sentinel.analytics" = [ "access_analytics" ];
        };
      };
      # Linkwarden
      groups."linkwarden.access" = { };
      # TODO for now linkwarden doesn't read groups from oidc anyway..
      # groups."linkwarden.admins" = { }; 
      systems.oauth2.linkwarden = {
        displayName = "Linkwarden";
        originUrl = "https://linkwarden.${config.homelab.ext-domain}/api/v1/auth/callback/authentik";
        originLanding = "https://linkwarden.${config.homelab.ext-domain}/";
        basicSecretFile = config.age.secrets.kanidm-oauth2-linkwarden.path;
        enableLegacyCrypto = true;
        scopeMaps."linkwarden.access" = [
          "openid"
          "email"
          "profile"
        ];
      };
      # Actual
      groups."actual.access" = { };
      systems.oauth2.actual = {
        displayName = "Actual";
        originUrl = "https://actual.${config.homelab.ext-domain}/openid/callback";
        originLanding = "https://actual.${config.homelab.ext-domain}/";
        basicSecretFile = config.age.secrets.kanidm-oauth2-actual.path;
        preferShortUsername = true;
        enableLegacyCrypto = true;
        scopeMaps."actual.access" = [
          "openid"
          "email"
          "profile"
        ];
      };
      # Mealie
      groups."mealie.access" = { };
      groups."mealie.admins" = { };
      systems.oauth2.mealie = {
        displayName = "Mealie";
        # Mealie's OIDC redirect URI is the frontend login route.
        originUrl = [
          "https://mealie.${config.homelab.ext-domain}/login"
          "https://mealie.${config.homelab.ext-domain}/"
        ];
        originLanding = "https://mealie.${config.homelab.ext-domain}/";
        basicSecretFile = config.age.secrets.kanidm-oauth2-mealie.path;
        preferShortUsername = true;
        enableLegacyCrypto = true;
        scopeMaps."mealie.access" = [
          "openid"
          "email"
          "profile"
          # Mealie requests a scope named after its OIDC_GROUPS_CLAIM
          # (mealie_roles). Grant that here and expose the readable role values
          # via the matching claim map below. Do NOT grant "groups": kanidm's
          # built-in groups claim would then be emitted as raw group SPNs
          # (mealie.access@<domain>, …) and clobber this claim map, leaving
          # Mealie unable to match against mealie-users / mealie-admins.
          "mealie_roles"
        ];
        claimMaps.mealie_roles = {
          joinType = "array";
          valuesByGroup = {
            "mealie.access" = [ "mealie-users" ];
            "mealie.admins" = [ "mealie-admins" ];
          };
        };
      };
      # Home Assistant (hass-oidc-auth custom component)
      groups."ha.access" = { };
      groups."ha.admins" = { };
      systems.oauth2.homeassistant = {
        displayName = "Home Assistant";
        # Public PKCE client — the component holds no secret. hass-oidc-auth
        # completes the flow at /auth/oidc/callback and lands the user on
        # /auth/oidc/welcome.
        public = true;
        originUrl = "https://ha.${config.homelab.ext-domain}/auth/oidc/callback";
        originLanding = "https://ha.${config.homelab.ext-domain}/auth/oidc/welcome";
        preferShortUsername = true;
        # The component reads roles from the built-in "groups" claim (raw group
        # SPNs like ha.access@<domain>); grant it alongside the standard scopes.
        scopeMaps."ha.access" = [
          "openid"
          "email"
          "profile"
          "groups"
        ];
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
