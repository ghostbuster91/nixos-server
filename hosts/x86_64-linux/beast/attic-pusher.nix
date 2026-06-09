{ config, ... }:
{
  age.secrets.attic-pusher-config.file = ../../../secrets/attic-pusher-config.age;

  services.attic-watch-store = {
    enable = true;
    cache = "malina5:system";
    credentialsFile = config.age.secrets.attic-pusher-config.path;
  };
}
