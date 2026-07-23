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

          # Build the closure on the target host itself instead of on the
          # machine running `deploy` (focusM2). Opt in only for hosts that are
          # capable build machines: beast (x86) and malina5 (Pi 5) build and
          # cache their own closure in place, so attic-watch-store captures the
          # outputs and focusM2 never accumulates the closure (nothing there for
          # gc to reap and re-pull). Deliberately NOT keyed on
          # `system == "aarch64-linux"`: that would also flip surfer (a weak
          # Banana Pi R3 with no build offload), forcing it to compile its whole
          # closure locally. surfer and thunder stay false and keep building via
          # focusM2's distributed builders (aarch64 → malina5).
          remoteBuild = builtins.elem name [ "beast" "malina5" ];
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
