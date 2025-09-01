{ config, ... }:
let domain = "headscale.${config.homelab.ext-domain}";
in {
  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/headscale";
      user = "headscale";
      group = "headscale";
      mode = "0700";
    }];
  };

  services = {
    headscale = {
      enable = true;
      address = "127.0.0.1";
      port = 8080;
      settings = {
        server_url = "https://${domain}";
        logtail.enabled = false;
        dns = {
          base_domain = "tail.${config.homelab.ext-domain}";
          nameservers.global = [ config.homelab.surfer.vlan.ip ];
        };
      };
    };

    nginx.virtualHosts.${domain} = {
      forceSSL = true;
      useACMEHost = config.homelab.ext-domain;

      locations."/" = {
        proxyPass =
          "http://localhost:${toString config.services.headscale.port}";
        proxyWebsockets = true;
      };
    };
  };

  environment.systemPackages = [ config.services.headscale.package ];
}
