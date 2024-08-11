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

  services.home-assistant = {
    enable = true;
    extraComponents = [
      # Components required to complete the onboarding
      "esphome"
      "met"
      "radio_browser"
    ];
    config = {
      # Includes dependencies for a basic setup
      # https://www.home-assistant.io/integrations/default_config/
      default_config = { };
      http = {
        server_host = "::1";
        trusted_proxies = [ "::1" ];
        use_x_forwarded_for = true;
      };
    };
  };

  services.nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
    # Use wildcard domain
    # useACMEHost = config.homelab.domain;
    serverName = "${roleName}.${config.homelab.domain}";
    forceSSL = true;
    sslCertificate = "/var/nginx-selfsigned.crt";
    sslCertificateKey = "/var/nginx-selfsigned.key";
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
