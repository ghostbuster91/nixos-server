let
  kghost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFeU4GXH+Ae00DipGGJN7uSqPJxWFmgRo9B+xjV3mK4";
  deckard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJF6U22I97ZyRPXJmJmlmvgHI7akGC8z/mlUVaCiLaOf";
in
{
  "nginx-selfsigned.key.age".publicKeys = [ kghost deckard ];
  "nginx-selfsigned.cert.age".publicKeys = [ kghost deckard ];
  "prometheus-hass-token.age".publicKeys = [ kghost deckard ];
  "alertmanager.age".publicKeys = [ kghost deckard ];

  "zigbee2mqtt-network-key.age".publicKeys = [ kghost deckard ];
  "mosquitto-pw-zigbee2mqtt.yaml.age".publicKeys = [ kghost deckard ];
  "mosquitto-pw-zigbee2mqtt.age".publicKeys = [ kghost deckard ];
  "mosquitto-pw-home_assistant.age".publicKeys = [ kghost deckard ];
}

