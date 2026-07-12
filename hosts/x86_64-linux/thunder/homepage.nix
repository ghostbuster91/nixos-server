{ config, ... }:
let
  port = 8082;
  domain = "home.${config.homelab.ext-domain}";
in
{
  services.homepage-dashboard = {
    enable = true;
    listenPort = port;
    # Homepage rejects requests whose Host header isn't allow-listed. nginx
    # forwards the original Host (recommendedProxySettings below), so the public
    # FQDN must be listed here.
    allowedHosts = domain;

    settings = {
      title = "Homelab";
      headerStyle = "clean";
    };

    # Starter content — expand as services come online.
    services = [
      {
        "AI" = [
          {
            "ComfyUI" = {
              href = "https://comfyui.${config.homelab.ext-domain}/";
              description = "Image generation";
            };
          }
        ];
      }
      {
        "Infra" = [
          {
            "Grafana" = {
              href = "https://grafana.${config.homelab.ext-domain}/";
              description = "Metrics & logs";
            };
          }
          {
            "Kanidm" = {
              href = "https://auth.${config.homelab.ext-domain}/";
              description = "Identity provider";
            };
          }
        ];
      }
    ];
  };

  # oauth2-proxy performs OIDC discovery against auth.<domain> at startup. On
  # thunder that name is served by the local unbound resolver, so if the daemon
  # starts before unbound is answering it dies with
  # "lookup auth.<domain>: no such host" and — with RestartSec=60 — fails the
  # whole deploy. unbound is Type=notify, so ordering After it waits until it is
  # genuinely ready to resolve.
  systemd.services.oauth2-proxy.after = [ "unbound.service" ];

  services.nginx = {
    upstreams.homepage = {
      servers."127.0.0.1:${toString port}" = { };
      extraConfig = ''
        zone homepage 64k;
        keepalive 2;
      '';
    };

    virtualHosts.${domain} = {
      forceSSL = true;
      useACMEHost = config.homelab.ext-domain;
      oauth2 = {
        enable = true;
        allowedGroups = [ "access_homepage" ];
      };
      locations."/" = {
        proxyPass = "http://homepage";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
