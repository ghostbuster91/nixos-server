{ self
, inputs
, ...
}: {
  perSystem = { pkgs, lib, system, ... }:
    let
      # Only check the configurations for the current system
      sysConfigs = lib.filterAttrs (_name: value: value.pkgs.system == system) self.nixosConfigurations;
    in
    {
      # Add all the nixos configurations to the checks
      checks = lib.mapAttrs' (name: value: { name = "nixos-toplevel-${name}"; value = value.config.system.build.toplevel; }) sysConfigs;


      devshells.default = {
        packages = [
          inputs.agenix.outputs.packages.${system}.agenix
          pkgs.nix
          pkgs.deploy-rs
          pkgs.age
          pkgs.nix
        ];
        commands =
          let
            flash-iso-image = name: image:
              let
                pv = "${pkgs.pv}/bin/pv";
                fzf = "${pkgs.fzf}/bin/fzf";
              in
              pkgs.writeShellScriptBin name ''
                set -euo pipefail

                # Build image
                nix build .#${image}

                # Display fzf disk selector
                iso="./result/iso/"
                iso="$iso$(ls "$iso" | ${pv})"
                dev="/dev/$(lsblk -d -n --output RM,NAME,FSTYPE,SIZE,LABEL,TYPE,VENDOR,UUID | awk '{ if ($1 == 1) { print } }' | ${fzf} | awk '{print $2}')"

                # Format
                ${pv} -tpreb "$iso" | sudo dd bs=4M of="$dev" iflag=fullblock conv=notrunc,noerror oflag=sync
              '';
          in
          [
            {
              package = pkgs.writeShellScriptBin "nix-build-deckard" ''
                set -euo pipefail
                nix build .#nixosConfigurations.deckard.config.system.build.toplevel
              '';
              help = "Builds toplevel NixOS image for deckard host";
            }
            {
              package = flash-iso-image "flash-deckard-iso" "live-iso";
              help = "Flash installer-iso image for deckard";
            }


            # todo interesting idea: execute system configuration as microvm
            # run-vm = {
            #   category = "Utils";
            #   description = "Executes a VM if output derivation contains one";
            #   exec = "exec ./result/bin/run-*-vm";
            # };
          ];
        env = [
          {
            # Additionally configure nix-plugins with our extra builtins file.
            # We need this for our repo secrets.
            name = "NIX_CONFIG";
            ## The patch is needed because otherwise we get:
            ## $ agenix -e meta.nix.age                                                                                              18:51:29
            ## error: could not dynamically open plugin file '"/nix/store/sbww4pi8vy1n8ssdxmyms33ksb4k3xb4-nix-plugins-15.0.0/lib/nix/plugins/libnix-extra-builtins.so"': 
            ## /nix/store/sbww4pi8vy1n8ssdxmyms33ksb4k3xb4-nix-plugins-15.0.0/lib/nix/plugins/libnix-extra-builtins.so: undefined symbol: _ZN3nix9EvalState12callFunctionERNS_5ValueEmPPS1_S2_NS_6PosIdxE
            ## https://github.com/shlevy/nix-plugins/issues/20
            value = ''
              plugin-files = ${pkgs.nix-plugins.overrideAttrs (o: {
                buildInputs = [pkgs.nixVersions.latest pkgs.boost];
                patches = (o.patches or []) ++ [ "${./..}/nix/nix-plugins.patch" ];
              })}/lib/nix/plugins
              extra-builtins-file = ${./..}/nix/extra-builtins.nix
            '';
          }
        ];
      };
    };
}
