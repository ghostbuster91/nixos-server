{ inputs
, ...
}: {
  perSystem = { pkgs, system, ... }:
    {
      # Add all the nixos configurations to the checks
      # checks = lib.mapAttrs' (name: value: { name = "nixos-toplevel-${name}"; value = value.config.system.build.toplevel; }) sysConfigs;

      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
        };
      };
      devshells.default = {
        packages = [
          inputs.agenix.outputs.packages.${system}.agenix
          pkgs.deploy-rs
          pkgs.age
          # nix-plugins 16.0.1 only builds against Nix 2.31's C++ API, and the
          # plugin must be loaded by the exact same Nix version. Pin the devshell
          # nix so the loader matches the plugin (default pkgs.nix is 2.34, which
          # both fails to build nix-plugins and is ABI-incompatible with it).
          pkgs.nixVersions.nix_2_31
          pkgs.cloudflared
          pkgs.borgbackup
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
            explore-backup = host:
              let
                agenix = inputs.agenix.outputs.packages.${system}.agenix;
                borg = "${pkgs.borgbackup}/bin/borg";
              in
              pkgs.writeShellScriptBin "explore-backup-${host}" ''
                set -euo pipefail

                repo_id="$(nix eval --raw .#nixosConfigurations.${host}.config.backup.repoId)"
                repo="ssh://''${repo_id}@''${repo_id}.repo.borgbase.com/./repo"

                workdir="$(mktemp -d -t explore-backup-${host}.XXXXXX)"
                mountpoint="$workdir/mnt"
                mkdir -p "$mountpoint"

                cleanup() {
                  ${borg} umount "$mountpoint" 2>/dev/null || true
                  rm -rf "$workdir"
                }
                trap cleanup EXIT

                ( cd secrets && ${agenix}/bin/agenix -d borgEncPass.age ) > "$workdir/pass"
                ( cd secrets && ${agenix}/bin/agenix -d borgSSHKey.age ) > "$workdir/sshkey"
                chmod 600 "$workdir/pass" "$workdir/sshkey"

                export BORG_REPO="$repo"
                export BORG_PASSCOMMAND="cat $workdir/pass"
                export BORG_RSH="ssh -i $workdir/sshkey -o StrictHostKeyChecking=accept-new"

                echo "Mounting borg repo for ${host} ($repo)..."
                ${borg} mount "$BORG_REPO" "$mountpoint"

                echo ""
                echo "Mounted at: $mountpoint"
                echo "Each archive (snapshot) appears as a subdirectory."
                echo "Exit this shell to unmount and clean up."
                echo ""

                cd "$mountpoint"
                exec "$SHELL"
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
            {
              package = explore-backup "deckard";
              help = "Mount deckard's BorgBase repo and drop into a subshell to browse it";
            }
            {
              package = explore-backup "thunder";
              help = "Mount thunder's BorgBase repo and drop into a subshell to browse it";
            }
            {
              package = explore-backup "beast";
              help = "Mount beast's BorgBase repo and drop into a subshell to browse it";
            }
            {
              package = explore-backup "malina5";
              help = "Mount malina5's BorgBase repo and drop into a subshell to browse it";
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
            value = ''
              plugin-files = ${pkgs.nix-plugins.override {nixComponents = pkgs.nixVersions.nixComponents_2_31;}}/lib/nix/plugins
              extra-builtins-file = ${./..}/nix/extra-builtins.nix
            '';
          }
        ];
      };
    };
}
