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
        ;

      mkDeploymentFor = system: name:
        {
          hostname = name;
          user = "root";
          sshUser = username;
          profiles.system.path =
            inputs.deploy-rs.lib.${system}.activate.nixos config.nixosConfigurations.${name};

          # If the previous profile should be re-activated if activation fails.
          # This defaults to `true`
          autoRollback = true;

          # See the earlier section about Magic Rollback for more information.
          # This defaults to `true`
          magicRollback = true;
          # remoteBuild = system == "aarch64-linux";
        };

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
    in
    {
      deploy.nodes =
        builtins.foldl'
          (acc: system:
            let
              mkDeployment = mkDeploymentFor system; # f { name, ... } -> deployment
            in
            acc //
            genAttrs (hostsFor system) (name: mkDeployment name)
          )
          { }
          systems;
    };
}
