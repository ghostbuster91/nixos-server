{ config, ... }:
{
  # malina5 runs oauth2-proxy purely to gate the Zigbee2MQTT frontend. The login
  # portal lives on thunder (oauth2.<domain>); malina5 only validates the shared
  # cookie via a local auth_request, so it must not serve a portal of its own.
  meta.oauth2-proxy.servePortal = false;

  # Gate the Zigbee2MQTT vhost (defined in the shared zigbee2mqtt module) behind
  # oauth2-proxy — admins only.
  services.nginx.virtualHosts."zigbee.${config.homelab.ext-domain}".oauth2 = {
    enable = true;
    allowedGroups = [ "access_zigbee" ];
  };
}
