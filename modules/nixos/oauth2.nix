{ config
, ...
}:
{
  meta.oauth2-proxy = {
    enable = true;
    cookieDomain = config.homelab.ext-domain;
    portalDomain = "oauth2.${config.homelab.ext-domain}";
    # TODO portal redirect to dashboard (in case someone clicks on kanidm "Web services")
  };

  age.secrets.oauth2-cookie-secret = {
    file = ../../secrets/oauth2-cookie-secret.age;
    mode = "440";
    group = "oauth2-proxy";
  };

  # Mirror the original oauth2 secret, but prepend OAUTH2_PROXY_CLIENT_SECRET=
  # so it can be used as an EnvironmentFile
  age.secrets.oauth2-client-secret = {
    # generator.dependencies = [
    #   config.age.secrets.kanidm-oauth2-web-sentinel
    # ];
    # generator.script =
    #   { lib
    #   , decrypt
    #   , deps
    #   , ...
    #   }:
    #   ''
    #     echo -n "OAUTH2_PROXY_CLIENT_SECRET="
    #     ${decrypt} ${lib.escapeShellArg (lib.head deps).file}
    #   '';
    file = ../../secrets/oauth2-cookie-client-secret.age;
    mode = "440";
    group = "oauth2-proxy";
  };

  services.oauth2-proxy =
    let
      clientId = "web-sentinel";
    in
    {
      provider = "oidc";
      scope = "openid email";
      loginURL = "https://auth.${config.homelab.ext-domain}/ui/oauth2";
      redeemURL = "https://auth.${config.homelab.ext-domain}/oauth2/token";
      validateURL = "https://auth.${config.homelab.ext-domain}/oauth2/openid/${clientId}/userinfo";
      clientID = clientId;
      email.domains = [ "*" ];

      extraConfig = {
        oidc-issuer-url = "https://auth.${config.homelab.ext-domain}/oauth2/openid/${clientId}";
        provider-display-name = "Kanidm";
        #skip-provider-button = true;
      };
    };

  systemd.services.oauth2-proxy.serviceConfig.EnvironmentFile = [
    config.age.secrets.oauth2-cookie-secret.path
    config.age.secrets.oauth2-client-secret.path
  ];
}
