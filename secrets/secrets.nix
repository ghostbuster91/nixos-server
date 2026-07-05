let
  kghost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFeU4GXH+Ae00DipGGJN7uSqPJxWFmgRo9B+xjV3mK4";
  deckard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJF6U22I97ZyRPXJmJmlmvgHI7akGC8z/mlUVaCiLaOf";
  thunder = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHBzMDaORL8CemRY6V3B2Ziif1wwU5O2j9sXc0O7dvgn";
  malina5 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBa0PJR7s0hD8Ht+obNNGavut8WlNNlX+Kax0bq83Xu1";
  beast = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDwcg1+0/b3eIKQUBwSNMHpo8dNIFCZmEWCEsmS3v6R3";
  surfer = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBkM0hU+Zrb1bOaMcwGO1DeM7u/jXIuCS9n7RqPYkYqH";
  focus = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ8CP9GdpB/9lLFpqmSB4CRayxS7nd7bmaxK7ZpYj8Az";
in
{
  "nginx-selfsigned.key.age".publicKeys = [ kghost deckard ];
  "nginx-selfsigned.cert.age".publicKeys = [ kghost deckard ];
  "prometheus-hass-token.age".publicKeys = [ kghost deckard malina5 ];
  "alertmanager.age".publicKeys = [ kghost deckard ];
  "grafana-secret-key.age".publicKeys = [ kghost deckard ];

  "zigbee2mqtt-network-key.age".publicKeys = [ kghost malina5 ];
  "mosquitto-pw-zigbee2mqtt.yaml.age".publicKeys = [ kghost malina5 ];
  "mosquitto-pw-zigbee2mqtt.age".publicKeys = [ kghost malina5 ];
  "mosquitto-pw-home_assistant.age".publicKeys = [ kghost malina5 ];
  "mosquitto-ampio-bridge-pw.age".publicKeys = [ kghost malina5 ];

  "acme-cloudflare-dns-token.age".publicKeys = [ kghost deckard thunder malina5 beast ];
  "acme-cloudflare-zone-token.age".publicKeys = [ kghost deckard thunder malina5 beast ];

  "meta.nix.age".publicKeys = [ kghost deckard thunder beast ];

  "borgEncPass.age".publicKeys = [ kghost deckard thunder malina5 beast ];
  "borgSSHKey.age".publicKeys = [ kghost deckard thunder malina5 beast ];

  "kanidm-selfsigned.key.age".publicKeys = [ kghost thunder ];
  "kanidm-selfsigned.cert.age".publicKeys = [ kghost thunder ];

  # replace with random agenix-rekey
  "kanidm-admin-password.age".publicKeys = [ kghost thunder ];
  "kanidm-idm-admin-password.age".publicKeys = [ kghost thunder ];
  "kanidm-oauth2-proxy.age".publicKeys = [ kghost thunder beast ];

  "kanidm-oauth2-grafana.age".publicKeys = [ kghost thunder deckard ];
  "kanidm-oauth2-linkwarden.age".publicKeys = [ kghost thunder beast ];
  "kanidm-oauth2-actual.age".publicKeys = [ kghost thunder malina5 ];
  "kanidm-oauth2-mealie.age".publicKeys = [ kghost thunder ];
  "mealie-oidc-env.age".publicKeys = [ kghost malina5 ];

  "oauth2-cookie-secret.age".publicKeys = [ kghost thunder beast ];
  "oauth2-cookie-client-secret.age".publicKeys = [ kghost thunder beast ];

  "cloudflared-tunnel.age".publicKeys = [ kghost thunder ];
  "postgres-linkwarden-password.age".publicKeys = [ kghost beast ];
  "nextauth-linkwarden-secret.age".publicKeys = [ kghost beast ];

  "beast-tailscale-key.age".publicKeys = [ kghost beast ];
  "mailna-tailscale-key.age".publicKeys = [ kghost malina5 ];
  "thunder-tailscale-key.age".publicKeys = [ kghost thunder ];

  "atticd-env.age".publicKeys = [ kghost malina5 ];
  "attic-pusher-config.age".publicKeys = [ kghost malina5 beast focus ];

  "wifiPassword.age".publicKeys = [ kghost surfer ];
  "legacyWifiPassword.age".publicKeys = [ kghost surfer ];
  "wlan00bssid.age".publicKeys = [ kghost surfer ];
  "wlan01bssid.age".publicKeys = [ kghost surfer ];
  "wlan10bssid.age".publicKeys = [ kghost surfer ];
  "surferFtKey.age".publicKeys = [ kghost surfer ];
}

