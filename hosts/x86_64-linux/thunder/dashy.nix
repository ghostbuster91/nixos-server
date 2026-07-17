{ config, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "apps.${ext}";
  svc = sub: "https://${sub}.${ext}/";
  # Render a tile only for users whose OIDC token carries `group` (emitted by
  # kanidm's dashy claimMaps.groups for members of the service's access group).
  # Merged onto a tile with //. Tiles without a gate are shown to everyone.
  gate = group: { displayData.showForKeycloakUsers.groups = [ group ]; };
in
{
  services.dashy = {
    enable = true;
    settings = {
      pageInfo.title = "Homelab";

      appConfig = {
        layout = "auto";
        iconSize = "medium";
        # Client-side OIDC against kanidm. `endpoint` is the per-client issuer;
        # oidc-client-ts discovers <endpoint>/.well-known/openid-configuration.
        # With no guest access, an anonymous visitor is redirected to kanidm to
        # log in. The `groups` claim (emitted by kanidm, see kanidm.nix) lands at
        # user.profile.groups and drives showForKeycloakUsers below.
        auth = {
          enableOidc = true;
          oidc = {
            clientId = "dashy";
            endpoint = "https://auth.${ext}/oauth2/openid/dashy";
            # Do NOT request the `groups` scope: kanidm denies authorization for
            # any scope the client isn't granted, and the dashy client's
            # scopeMaps grant only openid/email/profile. The groups *claim* is
            # still delivered via kanidm's claimMaps.groups regardless of scope
            # (same as the web-sentinel client), landing at user.profile.groups.
            scope = "openid email profile";
          };
        };
      };

      # Each tile is gated by the kanidm group that actually grants access to the
      # underlying service, so the board mirrors what a user can really reach.
      # This is cosmetic (URLs live in the static bundle); every service stays
      # gated by its own auth. Mattermost (own accounts), Kanidm (the IdP) and
      # Attic (token auth) have no kanidm group and are shown to everyone.
      sections = [
        {
          name = "Smart Home";
          items = [
            ({ title = "Home Assistant"; url = svc "ha"; description = "Home automation hub"; icon = "hl-home-assistant"; } // gate "ha")
            ({ title = "Zigbee2MQTT"; url = svc "zigbee"; description = "Zigbee device bridge"; icon = "hl-zigbee2mqtt"; } // gate "zigbee")
          ];
        }
        {
          name = "AI";
          items = [
            ({ title = "Open WebUI"; url = svc "chat"; description = "LLM chat"; icon = "hl-open-webui"; } // gate "openwebui")
            ({ title = "ComfyUI"; url = svc "comfyui"; description = "Image generation"; icon = "hl-comfyui"; } // gate "openwebui")
          ];
        }
        {
          name = "Apps";
          items = [
            ({ title = "Mealie"; url = svc "mealie"; description = "Recipes & meal planning"; icon = "hl-mealie"; } // gate "mealie")
            ({ title = "Stirling PDF"; url = svc "pdf"; description = "PDF toolkit"; icon = "hl-stirling-pdf"; } // gate "stirling")
            ({ title = "Paperless"; url = svc "paperless"; description = "Document archive"; icon = "hl-paperless-ngx"; } // gate "paperless")
            { title = "Mattermost"; url = svc "mattermost"; description = "Team chat"; icon = "hl-mattermost"; }
            # Own accounts (kept independent of OIDC), so shown to everyone.
            { title = "Vaultwarden"; url = svc "vault"; description = "Password manager"; icon = "hl-vaultwarden"; }
          ];
        }
        {
          name = "Infrastructure";
          items = [
            { title = "Kanidm"; url = svc "auth"; description = "Identity provider"; icon = "hl-authelia"; }
            { title = "Attic"; url = svc "attic"; description = "Nix binary cache"; icon = "hl-nixos"; }
            ({ title = "Grafana"; url = svc "grafana"; description = "Dashboards & metrics"; icon = "hl-grafana"; } // gate "grafana")
          ];
        }
      ];
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    locations."/" = {
      # Serve the pre-built static SPA. tryFiles falls back to index.html so the
      # client-side router (and the ?code=... OIDC callback on the origin) works.
      root = config.services.dashy.finalDrv;
      tryFiles = "$uri /index.html";
    };
  };
}
