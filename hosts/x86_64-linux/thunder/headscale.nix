{ config, ... }:
let domain = "headscale.${config.homelab.sec-domain}";
in {

  networking.firewall.allowedTCPPorts = [
    443
  ];
  environment.persistence = {
    "/persist".directories = [{
      directory = "/var/lib/headscale";
      user = "headscale";
      group = "headscale";
      mode = "0700";
    }];
  };

  # headscale fetches Tailscale's DERP map from controlplane.tailscale.com at
  # startup and hard-crashes if the lookup fails. thunder resolves via local
  # unbound (127.0.0.1), so a deploy that restarts both units concurrently can
  # start headscale before unbound answers -> "no such host" -> deploy-rs
  # rolls back. Order headscale after unbound so DNS is up first.
  systemd.services.headscale = {
    after = [ "unbound.service" ];
    wants = [ "unbound.service" ];
  };

  services = {
    headscale = {
      enable = true;
      address = "127.0.0.1";
      port = 8080;
      settings = {
        server_url = "https://${domain}";
        logtail.enabled = false;

        policy = {
          mode = "file";
          path = ./headscale-policy.hujson;
        };

        dns = {
          magic_dns = true;
          base_domain = "tail.${config.homelab.ext-domain}";
          nameservers.global = [
            config.homelab.thunder.vlan.ip
          ];
        };
      };
    };

    nginx.virtualHosts.${domain} = {
      forceSSL = true;
      useACMEHost = config.homelab.sec-domain;

      locations."/" = {
        proxyPass =
          "http://localhost:${toString config.services.headscale.port}";
        proxyWebsockets = true;
      };
    };
  };

  environment.systemPackages = [ config.services.headscale.package ];
}
