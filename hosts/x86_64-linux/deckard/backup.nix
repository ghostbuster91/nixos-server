{ config, pkgs, lib, ... }: {
  services.borgbackup.jobs =
    let
      snapName = "borgBackup";
      zfs = lib.getExe pkgs.zfs;
    in
    {
      "deckard" = {
        paths = [
          "/persist/.zfs/snapshot/${snapName}"
        ];
        # Note: you will need to edit the SSH url provided by BorgBase to match the below format
        repo = "m1n9honb@m1n9honb.repo.borgbase.com:repo";
        encryption = {
          mode = "repokey-blake2";
          passCommand = "cat ${config.age.secrets.borgEncPass.path}";
        };
        environment.BORG_RSH = "ssh -i ${config.age.secrets.borgSSHKey.path}";
        compression = "auto,lzma";
        startAt = "daily";

        prune.keep = {
          daily = 3;
          weekly = 2;
          monthly = 3;
        };

        preHook = ''
          snaps="$(${zfs} list -H -o name -t snapshot -r rpool1/safe/persist)"
          if printf '%s\n' "$snaps" | grep -qx "rpool1/safe/persist@${snapName}"; then
            ${zfs} destroy rpool1/safe/persist@${snapName}
          fi
          ${zfs} snapshot rpool1/safe/persist@${snapName}
        '';
        postHook = ''
          ${zfs} destroy rpool1/safe/persist@${snapName}
        '';
      };
    };

  programs.ssh.knownHosts = {
    borgbase = {
      hostNames = [ "m1n9honb.repo.borgbase.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMS3185JdDy7ffnr0nLWqVy8FaAQeVh1QYUSiNpW5ESq";
    };
  };
}
