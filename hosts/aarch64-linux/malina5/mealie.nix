{ config, ... }:
let
  clientId = "mealie";
  domain = "mealie.${config.homelab.ext-domain}";
in
{
  # OIDC client secret, shaped as an EnvironmentFile:
  #   OIDC_CLIENT_SECRET=<secret>
  # The raw secret also lives in kanidm-oauth2-mealie.age (kanidm's
  # basicSecretFile on thunder); keep the two in sync.
  age.secrets.mealie-oidc-env.file = ../../../secrets/mealie-oidc-env.age;

  environment.persistence."/persist" = {
    directories = [
      {
        directory = "/var/lib/private/mealie";
        mode = "0700";
      }
    ];
  };

  services.mealie = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9000;
    # Provides OIDC_CLIENT_SECRET; read by systemd as root before DynamicUser.
    credentialsFile = config.age.secrets.mealie-oidc-env.path;

    settings = {
      # Public URL — mealie derives its OIDC redirect_uri from this, so it must
      # be the externally reachable address, not the default localhost.
      BASE_URL = "https://${domain}";

      ALLOW_SIGNUP = "false";
      ALLOW_PASSWORD_LOGIN = "false";

      OIDC_AUTH_ENABLED = "true";
      OIDC_PROVIDER_NAME = "Kanidm";
      OIDC_CLIENT_ID = clientId;
      OIDC_CONFIGURATION_URL = "https://auth.${config.homelab.ext-domain}/oauth2/openid/${clientId}/.well-known/openid-configuration";
      # Auto-provision accounts for kanidm users who carry the group claim.
      OIDC_SIGNUP_ENABLED = "true";
      # Read roles from kanidm's custom claim map (mealie_roles), not the
      # built-in "groups" claim which returns raw group SPNs. Mealie also
      # requests a scope of this same name, which kanidm grants via its scopeMap.
      OIDC_GROUPS_CLAIM = "mealie_roles";
      OIDC_USER_GROUP = "mealie-users";
      OIDC_ADMIN_GROUP = "mealie-admins";
      # Keep the manual login page reachable; flip to "true" once OIDC is proven.
      OIDC_AUTO_REDIRECT = "true";
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.mealie.port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
