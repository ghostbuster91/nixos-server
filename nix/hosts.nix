{ inputs, ... }: {
  flake =
    { config
    , lib
    , ...
    }:
    let
      username = "kghost";

      inherit
        (lib)
        filterAttrs
        genAttrs
        mapAttrs
        ;

      # Creates a new nixosSystem with the correct specialArgs, pkgs and name definition
      mkHost = { minimal }: name:
        let
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
        inputs.nixpkgs.lib.nixosSystem
          {
            specialArgs = {
              # Use the correct instance lib that has our overlays
              inherit (pkgs-stable) lib;
              inherit (config) nodes;
              inherit inputs username pkgs-stable pkgs-unstable;
            };
            modules = [
              ../hosts/${name}
            ];
          };

      # Get all folders in hosts/
      hosts = builtins.attrNames (filterAttrs (_: type: type == "directory") (builtins.readDir ../hosts));
    in
    {
      nixosConfigurations = genAttrs hosts (mkHost { minimal = false; });

      # All nixosSystem instanciations are collected here, so that we can refer
      # to any system via nodes.<name>
      nodes = config.nixosConfigurations;
      # Add a shorthand to easily target toplevel derivations
      "@" = mapAttrs (_: v: v.config.system.build.toplevel) config.nodes;
    };
}
