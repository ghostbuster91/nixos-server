{ config, pkgs, username, ... }:
{
  # Give agenix access to the hostkey independent of impermanence activation
  age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  fileSystems."/persist".neededForBoot = true;
  fileSystems."/state".neededForBoot = true;

  environment.systemPackages = [
    (
      let
        persistenceConf = config.environment.persistence;
        directories = map (n: n.directory)
          (persistenceConf."/persist".directories ++ persistenceConf."/state".directories);
        files = map (n: n.file)
          (persistenceConf."/persist".files ++ persistenceConf."/state".files);
        allFiles = builtins.toJSON (files ++ directories);
      in
      pkgs.writeShellApplication {
        runtimeInputs = [
          pkgs.jq
          pkgs.gawk
          pkgs.zfs
        ];
        text = ''
          newFiles="$(zfs diff rpool1/local/root@blank | grep '+' | awk '{print $2}' | jq -R . | jq -s .)"
          persistedFiles='${allFiles}'
          notPersistedFiles="$(jq --argjson a "$newFiles" --argjson b "$persistedFiles" -n '$a - $b')"

          >&2 echo "Not persisted files:"
          echo "$notPersistedFiles"
        '';
        name = "zfs-diff";
      }
    )
  ];

  # State that should be kept across reboots, but is otherwise
  # NOT important information in any way that needs to be backed up.
  environment.persistence."/state" = {
    hideMounts = true;
    directories =
      [
        "/var/lib/nixos"
        "/var/log"
        {
          directory = "/var/lib/tailscale";
          mode = "0700";
        }
      ];
  };

  # State that should be kept forever, and backed up accordingly.
  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/machine-id"
      { file = "/var/keys/secret_file"; parentDirectory = { mode = "u=rwx,g=,o="; }; }
    ];
    # This should be specified in zsh module but the zsh module is hm-based
    # workaround for: https://github.com/nix-community/impermanence/issues/184
    users.${username} = {
      directories = [
        ".local/share/zsh_history"
      ];
    };
  };

  # https://github.com/nix-community/impermanence/issues/254
  system.activationScripts."createPersistentStorageDirs".deps = [ "var-lib-private-permissions" "users" "groups" ];
  system.activationScripts = {
    "var-lib-private-permissions" = {
      deps = [ "specialfs" ];
      text = ''
        mkdir -p /persist/var/lib/private
        chmod 0700 /persist/var/lib/private

        mkdir -p /state/var/lib/private
        chmod 0700 /state/var/lib/private
      '';
    };
  };
}
