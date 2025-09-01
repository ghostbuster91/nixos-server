let
  kghost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFeU4GXH+Ae00DipGGJN7uSqPJxWFmgRo9B+xjV3mK4";
  deckard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJF6U22I97ZyRPXJmJmlmvgHI7akGC8z/mlUVaCiLaOf";
  thunder = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHBzMDaORL8CemRY6V3B2Ziif1wwU5O2j9sXc0O7dvgn";
in
{
  "nginx-selfsigned.key.age".publicKeys = [ kghost deckard ];
  "nginx-selfsigned.cert.age".publicKeys = [ kghost deckard ];
  "prometheus-hass-token.age".publicKeys = [ kghost deckard ];
  "alertmanager.age".publicKeys = [ kghost deckard ];
  "grafana-secret-key.age".publicKeys = [ kghost deckard ];

  "zigbee2mqtt-network-key.age".publicKeys = [ kghost deckard ];
  "mosquitto-pw-zigbee2mqtt.yaml.age".publicKeys = [ kghost deckard ];
  "mosquitto-pw-zigbee2mqtt.age".publicKeys = [ kghost deckard ];
  "mosquitto-pw-home_assistant.age".publicKeys = [ kghost deckard ];
  "mosquitto-ampio-bridge-pw.age".publicKeys = [ kghost deckard ];

  "acme-cloudflare-dns-token.age".publicKeys = [ kghost deckard thunder ];
  "acme-cloudflare-zone-token.age".publicKeys = [ kghost deckard thunder ];

  "meta.nix.age".publicKeys = [ kghost deckard thunder ];

  "borgEncPass.age".publicKeys = [ kghost deckard thunder ];
  "borgSSHKey.age".publicKeys = [ kghost deckard thunder ];

  "kanidm-selfsigned.key.age".publicKeys = [ kghost deckard ];
  "kanidm-selfsigned.cert.age".publicKeys = [ kghost deckard ];

  # replace with random agenix-rekey
  "kanidm-admin-password.age".publicKeys = [ kghost deckard ];
  "kanidm-idm-admin-password.age".publicKeys = [ kghost deckard ];
  "kanidm-oauth2-grafana.age".publicKeys = [ kghost deckard ];
  "kanidm-oauth2-proxy.age".publicKeys = [ kghost deckard ];

  "oauth2-cookie-secret.age".publicKeys = [ kghost deckard ];
  "oauth2-cookie-client-secret.age".publicKeys = [ kghost deckard ];
}

