{ config, ... }:
let
  roleName = "ha";
in
{
  systemd.services.nginx = {
    requires = [ "home-assistant.service" ];
  };
  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];

  environment.persistence."/persist".directories = [
    {
      directory = config.services.home-assistant.configDir;
      user = "hass";
      group = "hass";
      mode = "0700";
    }
  ];

  services.home-assistant =
    let
      # Components required to complete the onboarding
      onboardingRequiredComponents = [
        "esphome"
        "met"
        "radio_browser"
      ];
    in
    {
      enable = true;
      extraComponents = onboardingRequiredComponents ++ [ "prometheus" ];
      config = {
        # Includes dependencies for a basic setup
        # https://www.home-assistant.io/integrations/default_config/
        default_config = { };
        http = {
          server_host = "::1";
          trusted_proxies = [ "::1" ];
          use_x_forwarded_for = true;
        };
        prometheus = { };
      };
    };

  services.nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
    # Use wildcard domain
    # useACMEHost = config.homelab.domain;
    serverName = "${roleName}.${config.homelab.domain}";

    sslCertificate = config.age.secrets."nginx-selfsigned.cert".path;
    sslCertificateKey = config.age.secrets."nginx-selfsigned.key".path;
    forceSSL = true;

    extraConfig = ''
      proxy_buffering off;
    '';
    locations."/" = {
      proxyPass = "http://[::1]:${toString config.services.home-assistant.config.http.server_port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
