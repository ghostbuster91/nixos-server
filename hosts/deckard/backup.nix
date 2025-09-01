{ config, ... }: {
  services.borgbackup.jobs = {
    "deckard" = {
      paths = [
        "/persist"
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
    };
  };

  programs.ssh.knownHosts = {
    borgbase = {
      hostNames = [ "m1n9honb.repo.borgbase.com" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMS3185JdDy7ffnr0nLWqVy8FaAQeVh1QYUSiNpW5ESq";
    };
  };
}
