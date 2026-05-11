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
in
(inputs.nixos-raspberrypi.lib.nixosSystemFull
{
  specialArgs = {
    inherit inputs username pkgs-unstable pkgs-stable;
    inherit (inputs) nixos-raspberrypi;
    inherit (config) nodes;
  };
  modules = [
    ./${name}
  ];
})
