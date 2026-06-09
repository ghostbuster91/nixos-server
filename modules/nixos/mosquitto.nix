{ config, lib, pkgs, ... }:
{
  age.secrets.mosquitto-pw-zigbee2mqtt = lib.mkIf config.services.zigbee2mqtt.enable {
    file = ../../secrets/mosquitto-pw-zigbee2mqtt.age;
    mode = "440";
    owner = "zigbee2mqtt";
    group = "mosquitto";
  };
  age.secrets.mosquitto-pw-home_assistant = lib.mkIf config.services.home-assistant.enable {
    file = ../../secrets/mosquitto-pw-home_assistant.age;
    mode = "440";
    owner = "hass";
    group = "mosquitto";
  };
  age.secrets.mosquitto-ampio-bridge-pw = {
    file = ../../secrets/mosquitto-ampio-bridge-pw.age;
    mode = "440";
    owner = "mosquitto";
    group = "mosquitto";
  };

  networking.firewall.allowedTCPPorts = [
    1883
  ];

  services.mosquitto = {
    enable = true;
    persistence = true;
    includeDirs = [ "/run/mosquitto/conf.d" ];
    listeners = [
      {
        acl = [ "pattern readwrite #" ];
        users = {
          zigbee2mqtt = lib.mkIf config.services.zigbee2mqtt.enable {
            passwordFile = config.age.secrets.mosquitto-pw-zigbee2mqtt.path;
            acl = [ "readwrite #" ];
          };
          home_assistant = lib.mkIf config.services.home-assistant.enable {
            passwordFile = config.age.secrets.mosquitto-pw-home_assistant.path;
            acl = [ "readwrite #" ];
          };
        };
        settings.allow_anonymous = false;
      }
    ];
  };

  # Render the ampio bridge connection at start-time so remote_password can
  # be sourced from an agenix secret — mosquitto's bridge `settings` has no
  # *File equivalent for that field. The `+` prefix runs the renderer as
  # root without mosquitto's sandbox: needed both because the module adds
  # every includeDirs path to ReadOnlyPaths, AND because the conf.d dir has
  # to exist before any sandboxed ExecStartPre can set up its namespace.
  # mkBefore puts this ahead of the module's listener-password preStart.
  systemd.services.mosquitto.serviceConfig.ExecStartPre = lib.mkBefore [
    "+${pkgs.writeShellScript "mosquitto-render-ampio-bridge" ''
      set -eu
      ${pkgs.coreutils}/bin/install -d -m 0750 -o mosquitto -g mosquitto /run/mosquitto/conf.d
      {
        echo "connection ampio"
        echo "addresses ampio.local:1883"
        echo "topic ampio/from/# in 0"
        echo "remote_username admin"
        echo "remote_password $(${pkgs.coreutils}/bin/cat ${config.age.secrets.mosquitto-ampio-bridge-pw.path})"
        # ampio's custom mosquitto auth plugin doesn't restore per-client
        # context when mosquitto resumes a persistent session, so every ACL
        # check on a clean_session=false connection fails with "context
        # missing - cannot authorize!" and the remote drops the bridge.
        # Forcing a fresh session each connect makes the plugin behave.
        echo "cleansession true"
      } > /run/mosquitto/conf.d/ampio.conf
      ${pkgs.coreutils}/bin/chown mosquitto:mosquitto /run/mosquitto/conf.d/ampio.conf
      ${pkgs.coreutils}/bin/chmod 0640 /run/mosquitto/conf.d/ampio.conf
    ''}"
  ];
}
