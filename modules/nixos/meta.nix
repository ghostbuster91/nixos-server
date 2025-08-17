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
}
