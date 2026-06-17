{ inputs, system, config, username, ... }:
# Creates a new nixosSystem with the correct specialArgs, pkgs and name definition
{ name }:
let
  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };
  pkgs-stable = import inputs.nixpkgs-stable {
    inherit system;
    config.allowUnfree = true;
  };

  baseSpecialArgs = {
    inherit inputs username pkgs-unstable pkgs-stable;
    inherit (config) nodes;
  };

  perHost = {
    default = {
      builder = inputs.nixpkgs.lib.nixosSystem;
      specialArgs = { };
    };
    malina5 = {
      builder = inputs.nixos-raspberrypi.lib.nixosSystemFull;
      specialArgs = { inherit (inputs) nixos-raspberrypi; };
    };
    surfer = {
      builder = inputs.nixos-sbc.inputs.nixpkgs.lib.nixosSystem;
      specialArgs = { };
    };
  };

  host = perHost.${name} or perHost.default;
in
host.builder {
  specialArgs = baseSpecialArgs // host.specialArgs;
  modules = [
    ./${name}
  ];
}
