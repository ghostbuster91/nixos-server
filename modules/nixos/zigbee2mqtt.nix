{ config
, ...
}:
let
  zigbeeDomain = "zigbee.${config.homelab.domain}";
in
{
  age.secrets."mosquitto-pw-zigbee2mqtt.yaml" = {
    file = ../../secrets/mosquitto-pw-zigbee2mqtt.yaml.age;
    mode = "440";
    owner = "zigbee2mqtt";
    group = "mosquitto";
  };
  age.secrets."zigbee2mqtt-network-key.yaml" = {
    file = ../../secrets/zigbee2mqtt-network-key.age;
    mode = "440";
    owner = "zigbee2mqtt";
  };
  environment.persistence."/persist".directories = [
    {
      directory = config.services.zigbee2mqtt.dataDir;
      user = "zigbee2mqtt";
      group = "zigbee2mqtt";
      mode = "0700";
    }
  ];

  topology.self.services.zigbee2mqtt.info = "https://${zigbeeDomain}";
  services.zigbee2mqtt = {
    enable = true;
    settings = {
      advanced = {
        log_level = "warn";
        network_key = "!${config.age.secrets."zigbee2mqtt-network-key.yaml".path} network_key";
        last_seen = "ISO_8601";
        transmit_power = 20;
      };
      availability = {
        enabled = true;
      };

      devices = {
        "0x0cae5ffffed02204" = { friendly_name = "homelab/temp1"; };
        "0x0cae5ffffed01f90" = { friendly_name = "homelab/temp2"; };
        "0x28dba7fffe818e3f" = { friendly_name = "homelab/bathroom/wall/temp1"; };
      };
      homeassistant = true;
      permit_join = true;
      serial = {
        port = "tcp://192.168.1.30:6638";
      };
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://localhost:${toString (builtins.head config.services.mosquitto.listeners).port}";
        user = "zigbee2mqtt";
        password = "!${config.age.secrets."mosquitto-pw-zigbee2mqtt.yaml".path} password";
      };
      # TODO once 1.30.3 is out
      # frontend.host = "/run/zigbee2mqtt/zigbee2mqtt.sock";
      frontend = {
        enabled = true;
        port = 8072;
      };
    };
  };

  services.nginx = {
    upstreams."zigbee2mqtt" = {
      servers."localhost:${toString config.services.zigbee2mqtt.settings.frontend.port}" = { };
      extraConfig = ''
        zone zigbee2mqtt 64k;
        keepalive 2;
      '';
    };
    virtualHosts."${zigbeeDomain}" = {
      serverName = "${zigbeeDomain}";
      sslCertificate = config.age.secrets."nginx-selfsigned.cert".path;
      sslCertificateKey = config.age.secrets."nginx-selfsigned.key".path;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://zigbee2mqtt";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
