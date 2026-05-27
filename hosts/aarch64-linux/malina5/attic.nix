{ config, ... }:
let
  domain = "attic.${config.homelab.ext-domain}";
in
{
  age.secrets.atticd-env.file = ../../../secrets/atticd-env.age;

  services.atticd = {
    enable = true;

    environmentFile = config.age.secrets.atticd-env.path;

    settings = {
      listen = "127.0.0.1:8080";

      api-endpoint = "https://${domain}/";

      chunking = {
        nar-size-threshold = 64 * 1024;
        min-size = 16 * 1024;
        avg-size = 64 * 1024;
        max-size = 256 * 1024;
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;

    locations."/" = {
      proxyPass = "http://${config.services.atticd.settings.listen}";
      extraConfig = ''
        client_max_body_size 0;
        proxy_request_buffering off;
      '';
    };
  };

  environment.persistence."/state" = {
    directories = [
      {
        directory = "/var/lib/atticd";
        user = "atticd";
        group = "atticd";
        mode = "0750";
      }
    ];
  };
}
