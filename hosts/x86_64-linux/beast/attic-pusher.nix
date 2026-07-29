{ config, ... }:
{
  age.secrets.attic-pusher-config.file = ../../../secrets/attic-pusher-config.age;

  services.attic-watch-store = {
    enable = true;
    cache = "malina5:system";
    # atticd is served at attic.<ext-domain> via thunder's VPN-only MagicDNS;
    # gate startup on it so a transient lookup miss during a deploy can't fail
    # activation and roll the node back.
    waitForHost = "attic.${config.homelab.ext-domain}";
    credentialsFile = config.age.secrets.attic-pusher-config.path;
  };
}
