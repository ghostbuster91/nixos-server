{ inputs
, ...
}: {
  perSystem = { pkgs, system, ... }:
    let
      # Getting `nixos-rebuild` to load our nix-plugins takes two fixes:
      #
      # 1. Pin its Nix to 2.30. The default `pkgs.nix-plugins` is built against
      #    Nix 2.30's C++ ABI, so only a 2.30 loader can resolve its symbols;
      #    2.31/2.34 fail with `undefined symbol: …` before the
      #    `ageImportEncrypted` builtin `meta.nix` needs is ever available.
      #    (Unlike agenix's pure `secrets.nix`, this eval genuinely needs the
      #    plugin, so we can't just strip it.) The override below shadows the
      #    system nixos-rebuild via the devshell PATH.
      #
      # 2. Disable re-exec (`_NIXOS_REBUILD_REEXEC=1`). Before building,
      #    nixos-rebuild-ng builds `config.system.build.nixos-rebuild` from the
      #    *target* config and `execve`s into it — and that copy uses the
      #    target's own Nix (2.34 on 26.05), which then reloads the 2.30 plugin
      #    and fails. Setting the guard env var makes it skip the re-exec and do
      #    the whole build with our 2.30 Nix. Safe here: our nixos-rebuild is the
      #    same 26.05 release as the targets.
      nixos-rebuild =
        let
          base = pkgs.nixos-rebuild-ng.override {
            nix = pkgs.nixVersions.nix_2_30;
          };
        in
        pkgs.writeShellScriptBin "nixos-rebuild" ''
          export _NIXOS_REBUILD_REEXEC=1
          exec ${base}/bin/nixos-rebuild "$@"
        '';
    in
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
          # The default `pkgs.nix-plugins` (16.0.1) is built against Nix 2.30's
          # C++ API, and the plugin must be loaded by that exact Nix version.
          # Pin the devshell nix to 2.30 so the loader matches the plugin. (Nix
          # 2.31 links but can't resolve `EvalState::allocBindings`; 2.34 is
          # fully ABI-incompatible — both fail with `undefined symbol` at load.)
          pkgs.nixVersions.nix_2_30
          # nixos-rebuild pinned to Nix 2.30 so it can load our nix-plugins
          # (see the `nixos-rebuild` binding above). Shadows the system one.
          nixos-rebuild
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
              plugin-files = ${pkgs.nix-plugins}/lib/nix/plugins
              extra-builtins-file = ${./..}/nix/extra-builtins.nix
            '';
          }
        ];
      };
    };
}
