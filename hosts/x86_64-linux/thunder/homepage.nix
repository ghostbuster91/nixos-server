{ config, ... }:
let
  port = 8082;
  domain = "apps.${config.homelab.ext-domain}";
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

    # Only hosts actually serving a vhost today. No siteMonitor: homepage probes
    # server-side from thunder, but headscale ACLs only let this (tagged) VPS
    # reach kanidm + DNS — not tag:ai/tag:media — so probes to the other hosts
    # would just error. Not worth widening the internet-facing VPS's reach for a
    # status dot.
    services =
      let
        svc = sub: attrs: {
          href = "https://${sub}.${config.homelab.ext-domain}/";
        } // attrs;
      in
      [
        {
          "Smart Home" = [
            { "Home Assistant" = svc "ha" { description = "Home automation hub"; icon = "home-assistant"; }; }
            { "Zigbee2MQTT" = svc "zigbee" { description = "Zigbee device bridge"; icon = "zigbee2mqtt"; }; }
          ];
        }
        {
          "AI" = [
            { "Open WebUI" = svc "chat" { description = "LLM chat"; icon = "open-webui"; }; }
            { "ComfyUI" = svc "comfyui" { description = "Image generation"; icon = "comfyui"; }; }
          ];
        }
        {
          "Apps" = [
            { "Mealie" = svc "mealie" { description = "Recipes & meal planning"; icon = "mealie"; }; }
            { "Mattermost" = svc "mattermost" { description = "Team chat"; icon = "mattermost"; }; }
          ];
        }
        {
          "Infrastructure" = [
            { "Kanidm" = svc "auth" { description = "Identity provider"; icon = "kanidm"; }; }
            { "Attic" = svc "attic" { description = "Nix binary cache"; icon = "nixos"; }; }
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
