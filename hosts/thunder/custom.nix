{ pkgs, username, ... }: {

  zramSwap.enable = true;

  networking.hostName = "thunder";
  networking.hostId = "5ada2fab";

  programs.zsh.enable = true;
  programs.zsh.histFile = "$HOME/.local/share/zsh_history";

  services = {
    openssh = {
      enable = true;
      settings.PermitRootLogin = "no";
      settings.PasswordAuthentication = false;
    };
  };

  security.sudo.wheelNeedsPassword = false;

  services.tailscale.enable = true;
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  users.users.${username} = {
    name = username;
    home = "/home/${username}";
    isNormalUser = true;
    extraGroups = [ "wheel" "network" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFeU4GXH+Ae00DipGGJN7uSqPJxWFmgRo9B+xjV3mK4" ];
    initialHashedPassword = "$y$j9T$aeZHaSe8QKeC0ruAi9TKo.$zooI/IZUwOupVDbMReaukiargPrF93H/wdR/.0zsrr.";
  };

  networking.firewall.allowedTCPPorts = [
    443
  ];

  nix = {
    # Automate garbage collection
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 60d";
    };

    # Flakes settings
    package = pkgs.nixVersions.stable;

    settings = {
      # Automate `nix store --optimise`
      auto-optimise-store = true;

      # Required by Cachix to be used as non-root user
      trusted-users = [ "root" username ];

      experimental-features = [ "nix-command" "flakes" ];
      warn-dirty = false;

      # Avoid unwanted garbage collection when using nix-direnv
      keep-outputs = true;
      keep-derivations = true;
    };
  };

  system.stateVersion = "25.05";
}
