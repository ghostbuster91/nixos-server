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

      mkDeployment = { user, system, }: name:
        {
          hostname = "${name}.local";
          inherit user;
          sshUser = username;
          profiles.system.path =
            inputs.deploy-rs.lib.${system}.activate.nixos config.nixosConfigurations.${name};
        };

      # Get all folders in hosts/
      hosts = builtins.attrNames (filterAttrs (_: type: type == "directory") (builtins.readDir ../hosts));
    in
    {
      deploy.nodes = genAttrs hosts (mkDeployment { user = "root"; system = "x86_64-linux"; });
    };
}
