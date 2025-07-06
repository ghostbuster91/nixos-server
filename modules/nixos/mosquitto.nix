{ config, ... }:
{
  age.secrets.mosquitto-pw-zigbee2mqtt = {
    file = ../../secrets/mosquitto-pw-zigbee2mqtt.age;
    mode = "440";
    owner = "zigbee2mqtt";
    group = "mosquitto";
  };
  age.secrets.mosquitto-pw-home_assistant = {
    file = ../../secrets/mosquitto-pw-home_assistant.age;
    mode = "440";
    owner = "hass";
    group = "mosquitto";
  };

  networking.firewall.allowedTCPPorts = [
    1883
  ];

  services.mosquitto = {
    enable = true;
    persistence = true;
    listeners = [
      {
        acl = [ "pattern readwrite #" ];
        users = {
          zigbee2mqtt = {
            passwordFile = config.age.secrets.mosquitto-pw-zigbee2mqtt.path;
            acl = [ "readwrite #" ];
          };
          home_assistant = {
            passwordFile = config.age.secrets.mosquitto-pw-home_assistant.path;
            acl = [ "readwrite #" ];
          };
        };
        settings.allow_anonymous = false;
      }
    ];
    bridges = {
      ampio = {
        addresses = [{ port = 1883; address = "ampio.local"; }];
        topics = [ "ampio/from/# in 0" ];
        settings = {
          remote_username = "admin";

          # TODO: fix me!
          remote_password = "blaghtway4";
        };
      };
    };
  };
}
