{
  nix.buildMachines = [{
    hostName = "malina5";
    sshUser = "nix-remote-builder";
    sshKey = "/home/kghost/.ssh/nixremote";
    system = "aarch64-linux";
    protocol = "ssh-ng";
    maxJobs = 3;
    speedFactor = 2;
    supportedFeatures = [ "nixos-test" "benchmark" "big-parallel" "kvm" ];
    mandatoryFeatures = [ ];
  }];
  # required, otherwise remote buildMachines above aren't used
  nix.distributedBuilds = true;
  nix.extraOptions = ''
    builders-use-substitutes = false
  '';

  programs.ssh.knownHosts = {
    rpiBuilder = {
      hostNames = [ "malina5" ];
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBa0PJR7s0hD8Ht+obNNGavut8WlNNlX+Kax0bq83Xu1";
    };
  };
}
