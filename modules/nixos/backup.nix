{ lib, pkgs, config, ... }:
let
  inherit (lib) mkOption types getExe concatMapStrings;
  zfs = getExe pkgs.zfs;
  mount = "${pkgs.util-linux}/bin/mount";
  umount = "${pkgs.util-linux}/bin/umount";
  snapName = "borgBackup";
  primaryDataset = { dataset = "rpool1/safe/persist"; mountpoint = "/persist"; };
  # Stable explicit mount path inside the service's private /tmp.
  # Using .zfs/snapshot/ automount is unreliable: ZFS auto-unmounts it on
  # last-close (when ls finishes), leaving borg a stale dentry → 0 files.
  snapMount = ds: "/tmp/borg-snap-${builtins.replaceStrings ["/"] ["-"] (lib.strings.removePrefix "/" ds.mountpoint)}";
  mkSnapHook = ds: ''
    snaps="$(${zfs} list -H -o name -t snapshot -r ${ds.dataset})"
    if printf '%s\n' "$snaps" | grep -qx "${ds.dataset}@${snapName}"; then
      ${zfs} destroy ${ds.dataset}@${snapName}
    fi
    ${zfs} snapshot ${ds.dataset}@${snapName}
    mkdir -p ${snapMount ds}
    ${mount} -t zfs ${ds.dataset}@${snapName} ${snapMount ds}
  '';
  mkDestroyHook = ds: ''
    ${umount} ${snapMount ds} || true
    rmdir ${snapMount ds} || true
    ${zfs} destroy ${ds.dataset}@${snapName} || true
  '';
  mkBackupJob =
    { name
    , repository
    , datasets ? [ primaryDataset ]
    , paths ? map snapMount datasets
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

        extraCreateArgs = "--stats";

        prune.keep = pruneKeep;

        preHook = concatMapStrings mkSnapHook datasets;

        postHook = concatMapStrings mkDestroyHook datasets;
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
  options.backup.extraDatasets = mkOption {
    type = types.listOf (types.submodule {
      options = {
        dataset = mkOption { type = types.str; description = "ZFS dataset name (e.g. dpool/safe/persist)"; };
        mountpoint = mkOption { type = types.str; description = "Dataset mount point (e.g. /data/persist)"; };
      };
    });
    default = [ ];
    description = "Additional ZFS datasets to include in the backup alongside the primary rpool1/safe/persist.";
  };

  config = {
    age.secrets.borgEncPass.file = ../../secrets/borgEncPass.age;
    age.secrets.borgSSHKey.file = ../../secrets/borgSSHKey.age;

    services.borgbackup.jobs =
      mkBackupJob {
        name = config.backup.name;
        repository = "${config.backup.repoId}@${hostname}:repo";
        datasets = [ primaryDataset ] ++ config.backup.extraDatasets;
      };

    programs.ssh.knownHosts = {
      borgbase = {
        hostNames = [ hostname ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMS3185JdDy7ffnr0nLWqVy8FaAQeVh1QYUSiNpW5ESq";
      };
    };
  };
}
