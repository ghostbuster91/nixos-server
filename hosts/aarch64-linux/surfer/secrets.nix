{ config, ... }:
let
  hostapdSecrets = {
    wifiPassword = ../../../secrets/wifiPassword.age;
    legacyWifiPassword = ../../../secrets/legacyWifiPassword.age;
    wlan00bssid = ../../../secrets/wlan00bssid.age;
    wlan01bssid = ../../../secrets/wlan01bssid.age;
    wlan10bssid = ../../../secrets/wlan10bssid.age;
  };
in
{
  age.secrets = builtins.mapAttrs (_: file: { inherit file; }) hostapdSecrets;

  # agenix has no built-in restartUnits; trigger a restart whenever any
  # encrypted source file's store path changes (i.e. its plaintext changed).
  systemd.services.hostapd.restartTriggers =
    builtins.map (name: config.age.secrets.${name}.file)
      (builtins.attrNames hostapdSecrets);
}
