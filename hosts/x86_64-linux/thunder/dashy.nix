{ config, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "apps.${ext}";
  svc = sub: "https://${sub}.${ext}/";
in
{
  # Dashy replaces homepage-dashboard. Unlike homepage, dashy renders per-user
  # from the OIDC token itself, so the whole board no longer needs an
  # oauth2-proxy group gate in front — dashy runs the OIDC flow client-side
  # (oidc-client-ts, auth-code + PKCE) and hides tiles the user's groups don't
  # grant. See the Grafana tile below.
  #
  # nixpkgs ships dashy as a *static* SPA (no node backend): server-side status
  # checks and UI config-writes are unavailable, but client-side OIDC login and
  # group-based visibility work fine — that's all this needs.
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
            scope = "openid email profile groups";
          };
        };
      };

      sections = [
        {
          name = "Smart Home";
          items = [
            { title = "Home Assistant"; url = svc "ha"; description = "Home automation hub"; icon = "hl-home-assistant"; }
            { title = "Zigbee2MQTT"; url = svc "zigbee"; description = "Zigbee device bridge"; icon = "hl-zigbee2mqtt"; }
          ];
        }
        {
          name = "AI";
          items = [
            { title = "Open WebUI"; url = svc "chat"; description = "LLM chat"; icon = "hl-open-webui"; }
            { title = "ComfyUI"; url = svc "comfyui"; description = "Image generation"; icon = "hl-comfyui"; }
          ];
        }
        {
          name = "Apps";
          items = [
            { title = "Mealie"; url = svc "mealie"; description = "Recipes & meal planning"; icon = "hl-mealie"; }
            { title = "Mattermost"; url = svc "mattermost"; description = "Team chat"; icon = "hl-mattermost"; }
          ];
        }
        {
          name = "Infrastructure";
          items = [
            { title = "Kanidm"; url = svc "auth"; description = "Identity provider"; icon = "hl-authelia"; }
            { title = "Attic"; url = svc "attic"; description = "Nix binary cache"; icon = "hl-nixos"; }
            # Rendered only for users whose OIDC token carries the "grafana" group
            # value — kanidm emits it for grafana.access members (kanidm.nix). For
            # everyone else the tile is filtered out client-side and never shown.
            # This is cosmetic: Grafana itself stays gated by its own OIDC.
            {
              title = "Grafana";
              url = svc "grafana";
              description = "Dashboards & metrics";
              icon = "hl-grafana";
              displayData.showForKeycloakUsers.groups = [ "grafana" ];
            }
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
