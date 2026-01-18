{ inputs, system, lib, config, username, ... }:
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
(inputs.nixpkgs.lib.nixosSystem
{
  specialArgs = {
    # Use the correct instance lib that has our overlays
    inherit (pkgs-stable) lib;
    inherit (config) nodes;
    inherit inputs username pkgs-stable pkgs-unstable;
  };
  modules = [
    ./${name}
  ];
})


