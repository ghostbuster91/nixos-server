{ self, inputs, ... }: {
  perSystem =
    { pkgs
    , system
    , ...
    }: {
      # For each major system, we provide a customized installer image that
      # has ssh and some other convenience stuff preconfigured.
      # Not strictly necessary for new setups.
      packages.live-iso = inputs.nixos-generators.nixosGenerate {
        inherit pkgs;
        modules = [
          inputs.disko.nixosModules.disko
          ./installer-configuration.nix
          # ../config/ssh.nix
          ({ config
           , lib
           , pkgs
           , ...
           }:
            let
              # disko
              disko = pkgs.writeShellScriptBin "disko" ''${config.system.build.diskoScript}'';
              disko-mount = pkgs.writeShellScriptBin "disko-mount" "${config.system.build.mountScript}";
              disko-format = pkgs.writeShellScriptBin "disko-format" "${config.system.build.formatScript}";
              disko-destroy = pkgs.writeShellScriptBin "disko-destroy" "${config.system.build.destroyScriptNoDeps}";

              # system
              system = self.nixosConfigurations.deckard.config.system.build.toplevel;

              install-system = pkgs.writeShellScriptBin "install-system" ''
                set -euo pipefail

                echo "Formatting disks..."
                . ${disko-format}/bin/disko-format

                echo "Mounting disks..."
                . ${disko-mount}/bin/disko-mount

                echo "Installing system..."
                nixos-install --system ${system}

                echo "Done!"
              '';
            in
            {
              imports = [
                (import ../hosts/deckard/disko-config.nix { })
              ];

              # we don't want to generate filesystem entries on this image
              disko.enableConfig = lib.mkDefault false;

              # add disko commands to format and mount disks
              environment.systemPackages = [
                disko
                disko-mount
                disko-format
                disko-destroy
                install-system
              ];
            })
        ];
        format =
          {
            x86_64-linux = "install-iso";
            aarch64-linux = "sd-aarch64-installer";
          }.${system};
      };
    };
}
