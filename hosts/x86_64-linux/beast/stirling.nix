{ config, ... }:
let
  clientId = "stirling";
  # Provider slug — must match the callback path registered with kanidm below:
  #   https://pdf.<domain>/login/oauth2/code/kanidm
  provider = "kanidm";
  port = 8083;
  domain = "pdf.${config.homelab.ext-domain}";
in
{
  # OIDC client secret, shaped as an EnvironmentFile:
  #   SECURITY_OAUTH2_CLIENTSECRET=<secret>
  # The raw secret also lives in kanidm-oauth2-stirling.age (kanidm's
  # basicSecretFile on thunder); keep the two in sync.
  age.secrets.stirling-oidc-env.file = ../../../secrets/stirling-oidc-env.age;

  # Native login persists a user-account database (H2) under the state dir.
  environment.persistence."/persist" = {
    directories = [
      {
        directory = "/var/lib/stirling-pdf";
        mode = "0700";
      }
    ];
  };

  services.stirling-pdf = {
    enable = true;
    # SECURITY_OAUTH2_CLIENTSECRET is delivered via the agenix env file so the
    # secret never lands in the nix store.
    environmentFiles = [ config.age.secrets.stirling-oidc-env.path ];
    environment = {
      # Bind loopback only; nginx terminates TLS and reverse-proxies.
      SERVER_ADDRESS = "127.0.0.1";
      SERVER_PORT = port;

      # Turn on Stirling's login system and wire it to kanidm via OIDC.
      SECURITY_ENABLELOGIN = true;
      SECURITY_OAUTH2_ENABLED = true;
      SECURITY_OAUTH2_PROVIDER = provider;
      # kanidm's OIDC issuer for this client. Stirling appends
      # /.well-known/openid-configuration itself, so it must NOT be included here.
      SECURITY_OAUTH2_ISSUER = "https://auth.${config.homelab.ext-domain}/oauth2/openid/${clientId}";
      SECURITY_OAUTH2_CLIENTID = clientId;
      SECURITY_OAUTH2_SCOPES = "openid,profile,email";
      SECURITY_OAUTH2_USEASUSERNAME = "email";
      # Auto-provision a Stirling account on first login; kanidm's scopeMap
      # already restricts who can obtain a token (the stirling.access group).
      SECURITY_OAUTH2_AUTOCREATEUSER = true;
      SECURITY_OAUTH2_BLOCKREGISTRATION = false;
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
