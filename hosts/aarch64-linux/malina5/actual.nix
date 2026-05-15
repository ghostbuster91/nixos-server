{ config, ... }: {

  # Mirror the original oauth2 secret
  age.secrets.actual-oauth2-client-secret = {
    file = ../../../secrets/kanidm-oauth2-actual.age;
    owner = "root";
    group = "actual-secrets";
    mode = "0440";
  };

  environment.persistence."/persist" = {
    directories = [
      {
        directory = "/var/lib/private/actual";
        mode = "0700";
      }
    ];
  };
  users.groups.actual-secrets = { };
  systemd.services.actual.serviceConfig.SupplementaryGroups = [
    "actual-secrets"
  ];

  services.actual = {
    enable = true;

    settings = {
      hostname = "127.0.0.1";
      port = 5006;

      loginMethod = "openid";
      allowedLoginMethods = [ "openid" ];
      userCreationMode = "login";
      enforceOpenId = true;
      openId =
        let
          clientId = "actual";
        in
        {
          discoveryURL = "https://auth.${config.homelab.ext-domain}/oauth2/openid/${clientId}/.well-known/openid-configuration";
          client_id = clientId;
          client_secret._secret = config.age.secrets.actual-oauth2-client-secret.path;
          server_hostname = "https://actual.${config.homelab.ext-domain}";
          authMethod = "openid";
        };
    };
  };

  services.nginx.virtualHosts."actual.${config.homelab.ext-domain}" = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.actual.settings.port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
