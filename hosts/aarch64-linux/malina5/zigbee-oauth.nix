{ config, pkgs, ... }:
{
  # malina5 runs oauth2-proxy purely to gate the Zigbee2MQTT frontend. The login
  # portal lives on thunder (oauth2.<domain>); malina5 only validates the shared
  # cookie via a local auth_request, so it must not serve a portal of its own.
  meta.oauth2-proxy.servePortal = false;

  systemd.services.oauth2-proxy = {
    # oauth2-proxy resolves auth.<domain> via thunder's DNS over tailscale at
    # startup (OIDC discovery). Order it after tailscale so the tailnet is up.
    after = [ "tailscaled.service" ];

    # tailscaled being "active" doesn't guarantee the tailnet is reachable yet,
    # so also block start until the issuer actually resolves. Without this a cold
    # boot/switch races DNS -> "no such host" -> RestartSec=60 -> deploy rollback.
    serviceConfig.ExecStartPre = "${pkgs.writeShellScript "wait-for-auth-dns" ''
      for _ in $(seq 1 60); do
        ${pkgs.getent}/bin/getent hosts auth.${config.homelab.ext-domain} && exit 0
        sleep 2
      done
      echo "auth.${config.homelab.ext-domain} did not resolve within 120s" >&2
      exit 1
    ''}";
  };

  # Gate the Zigbee2MQTT vhost (defined in the shared zigbee2mqtt module) behind
  # oauth2-proxy — admins only.
  services.nginx.virtualHosts."zigbee.${config.homelab.ext-domain}".oauth2 = {
    enable = true;
    allowedGroups = [ "access_zigbee" ];
  };
}
