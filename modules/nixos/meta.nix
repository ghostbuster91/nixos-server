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

  options.homelab.ext-domain = mkOption {
    type = types.str;
  };

  options.homelab.sec-domain = mkOption {
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

  options.homelab.malina5.vlan.ip = mkOption {
    type = types.str;
  };

  options.homelab.beast.vlan.ip = mkOption {
    type = types.str;
  };

  options.homelab.vpnCidr = mkOption {
    type = types.str;
  };

  # The home LAN behind the Orange FunBox. Values live in secrets/meta.nix.age
  # so the repo never publishes the layout of the house network; `devices` is a
  # free-form attrset so adding one needs a secret edit, not an option here.
  options.homelab.lan = {
    cidrv4 = mkOption {
      description = "CIDRv4 of the home LAN.";
      type = types.str;
    };

    gateway.ip = mkOption {
      description = "The ISP gateway (FunBox) -- default route and DHCP server for the home LAN.";
      type = types.str;
    };

    devices = mkOption {
      description = "Fixed-address non-NixOS devices on the home LAN, by short name.";
      default = { };
      type = types.attrsOf (types.submodule {
        options.ip = mkOption {
          description = "The device IPv4 address on the home LAN.";
          type = types.str;
        };
      });
    };
  };

}
