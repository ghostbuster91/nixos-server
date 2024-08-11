{ self, inputs, lib, ... }:
let
  username = "kghost";
  system = "x86_64-linux";
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
  pkgs-stable = import inputs.nixpkgs-stable {
    inherit system;
    config.allowUnfree = true;
  };
in
{
  flake.nixosConfigurations = {
    deckard =
      lib.nixosSystem {
        modules = [ ./deckard ];
        specialArgs = {
          inherit inputs; inherit username; inherit pkgs-stable; inherit pkgs-unstable;
        };
      };
  };

  perSystem = { pkgs, lib, system, ... }:
    let
      # Only check the configurations for the current system
      sysConfigs = lib.filterAttrs (_name: value: value.pkgs.system == system) self.nixosConfigurations;
    in
    {
      # Add all the nixos configurations to the checks
      checks = lib.mapAttrs' (name: value: { name = "nixos-toplevel-${name}"; value = value.config.system.build.toplevel; }) sysConfigs;
    };
}
