# Registers the homelab attic binary cache (served by malina5 at
# attic.<ext-domain>/system) as a Nix substituter + trusted key.
#
# Import this on any host that should *consume* the cache. Notably malina5
# itself needs it: as the aarch64 remote builder it otherwise rebuilds from
# source whenever nix-gc has evicted a path from its local store, since it
# can't pull its own cached NARs back without listing the cache here.
#
# Consuming hosts must also import the meta module (for homelab.ext-domain).
# The signing pubkey is the cache's public key (independent of the domain);
# regenerating the atticd keypair means updating this value and flake.nix.
{ config, ... }:
{
  nix.settings = {
    extra-substituters = [ "https://attic.${config.homelab.ext-domain}/system" ];
    extra-trusted-public-keys = [
      "system:WOAVhhRoFrTy1MfcJyEzHLOa737CJZOGZccwOiwhfoU="
    ];
  };
}
