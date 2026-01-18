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

      # Get all folders in hosts/
      systems =
        builtins.attrNames (
          filterAttrs (_: type: type == "directory")
            (builtins.readDir ../hosts)
        );

      hostsFor = system:
        builtins.attrNames (
          filterAttrs (_: type: type == "directory")
            (builtins.readDir ../hosts/${system})
        );
      mkHostFor = system:
        import ../hosts/${system} {
          inherit inputs system username config lib;
        };
    in
    {
      nixosConfigurations =
        builtins.foldl'
          (acc: system:
            let
              mkHost = mkHostFor system; # f { name, ... } -> nixosSystem
            in
            acc //
            genAttrs (hostsFor system) (name:
              mkHost { inherit name; }
            )
          )
          { }
          systems;
      # All nixosSystem instanciations are collected here, so that we can refer
      # to any system via nodes.<name>
      nodes = config.nixosConfigurations;
      # Add a shorthand to easily target toplevel derivations
      "@" = mapAttrs (_: v: v.config.system.build.toplevel) config.nodes;
    };
}
