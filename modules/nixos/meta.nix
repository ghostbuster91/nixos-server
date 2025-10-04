{ lib, ... }:
let
  inherit
    (lib)
    mkOption
    types
    ;
  # Try to access the extra builtin we loaded via nix-plugins.
  # Throw an error if that doesn't exist.
  ageImportEncrypted =
    assert lib.assertMsg (builtins ? extraBuiltins.ageImportEncrypted)
      "The extra builtin 'ageImportEncrypted' is not available, so repo.secrets cannot be decrypted. Did you forget to add nix-plugins and point it to `./nix/extra-builtins.nix` ?";
    builtins.extraBuiltins.ageImportEncrypted;

  addrType = types.submodule {
    options = {
      address = mkOption { type = types.str; };
      prefixLength = mkOption { type = types.int; };
    };
  };

  ifaceType = types.submodule ({ ... }: {
    options = {
      ipv4.addresses = mkOption { type = types.listOf addrType; default = [ ]; };
      ipv6.addresses = mkOption { type = types.listOf addrType; default = [ ]; };
      ipv4.routes = mkOption { type = types.listOf addrType; default = [ ]; };
      ipv6.routes = mkOption { type = types.listOf addrType; default = [ ]; };
    };
  });
in
{

  imports =
    let
      masterIdentities = [ "/home/kghost/.ssh/id_ed25519" ];
    in
    [
      (ageImportEncrypted masterIdentities ../../secrets/meta.nix.age)
    ];

  options.homelab.domain = mkOption {
    type = types.str;
  };

  options.homelab.hostname = mkOption {
    type = types.str;
  };

  options.homelab.ext-domain = mkOption {
    type = types.str;
  };

  options.homelab.vps.interfaces = mkOption {
    type = types.attrsOf ifaceType;
    default = { };
  };

  options.homelab.surfer.vlan.ip = mkOption {
    type = types.str;
  };

  options.homelab.deckard.vlan.ip = mkOption {
    type = types.str;
  };

  options.homelab.thunder.vlan.ip = mkOption {
    type = types.str;
  };

  options.homelab.vpnCidr = mkOption {
    type = types.str;
  };

}
