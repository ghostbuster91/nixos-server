{ config, pkgs, username, ... }:
{
  # Give agenix access to the hostkey independent of impermanence activation
  age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

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
  fileSystems."/state".neededForBoot = true;
  environment.persistence."/state" = {
    hideMounts = true;
    directories =
      [
        "/var/lib/systemd"
        "/var/log"
        "/etc/NetworkManager/system-connections"
      ];
  };

  # State that should be kept forever, and backed up accordingly.
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/machine-id"
      { file = "/var/keys/secret_file"; parentDirectory = { mode = "u=rwx,g=,o="; }; }
    ];
    directories = [
      "/var/lib/nixos"
      { directory = "/var/lib/colord"; user = "colord"; group = "colord"; mode = "u=rwx,g=rx,o="; }
    ];
    # This should be specified in zsh module but the zsh module is hm-based
    # workaround for: https://github.com/nix-community/impermanence/issues/184
    users.${username} = {
      directories = [
        ".local/share/zsh_history"
      ];
    };
  };
}
