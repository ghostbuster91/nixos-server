{ lib, pkgs, config, ... }:
let
  inherit (lib) mkOption types getExe;
  zfs = getExe pkgs.zfs;
  snapName = "borgBackup";
  # ta funkcja robi dokładnie Twojego joba, tylko parametryzowanego
  mkBackupJob =
    { name
    , repository
    , dataset ? "rpool1/safe/persist"
    , paths ? [ "/persist/.zfs/snapshot/${snapName}" ]
    , startAt ? "daily"
    , compression ? "auto,lzma"
    , pruneKeep ? { daily = 3; weekly = 2; monthly = 3; }
    , encryptionMode ? "repokey-blake2"
    , passSecret ? "borgEncPass"
    , sshKeySecret ? "borgSSHKey"
    }:
    {
      "${name}" = {
        inherit paths compression startAt;

        repo = repository;

        encryption = {
          mode = encryptionMode;
          passCommand = "cat ${config.age.secrets.${passSecret}.path}";
        };

        environment.BORG_RSH = "ssh -i ${config.age.secrets.${sshKeySecret}.path}";

        prune.keep = pruneKeep;

        preHook = ''
          snaps="$(${zfs} list -H -o name -t snapshot -r ${dataset})"
          if printf '%s\n' "$snaps" | grep -qx "${dataset}@${snapName}"; then
            ${zfs} destroy ${dataset}@${snapName}
          fi
          ${zfs} snapshot ${dataset}@${snapName}
        '';

        postHook = ''
          ${zfs} destroy ${dataset}@${snapName}
        '';
      };
    };
  hostname = "${config.backup.repoId}.repo.borgbase.com";
in
{
  options.backup.name = mkOption {
    type = types.str;
  };
  options.backup.repoId = mkOption {
    type = types.str;
  };

  config = {
    age.secrets.borgEncPass.file = ../../secrets/borgEncPass.age;
    age.secrets.borgSSHKey.file = ../../secrets/borgSSHKey.age;

    services.borgbackup.jobs =
      mkBackupJob {
        name = config.backup.name;
        repository = "${config.backup.repoId}@${hostname}:repo";
      };

    programs.ssh.knownHosts = {
      borgbase = {
        hostNames = [ hostname ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMS3185JdDy7ffnr0nLWqVy8FaAQeVh1QYUSiNpW5ESq";
      };
    };
  };
}
