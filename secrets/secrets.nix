let
  kghost = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFeU4GXH+Ae00DipGGJN7uSqPJxWFmgRo9B+xjV3mK4";
  users = [ kghost ];

  deckard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID+d9WDqu+Wq5zy+lxASNMMWi2ZzJk8KRssDN+5JwQKp";
  systems = [ deckard ];
in
{
  "nginx-selfsigned.key.age".publicKeys = [ kghost deckard ];
  "nginx-selfsigned.cert.age".publicKeys = [ kghost deckard ];
}

