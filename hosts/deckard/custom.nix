{ pkgs, username, ... }:
{
  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  # boot.loader.grub.device = "/dev/sda";

  networking = {
    hostName = "deckard"; # Define your hostname.
    hostId = "69163a45";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [
      80
      443
    ];
  };
  services = {
    openssh = {
      # Easiest to use and most distros use this by default.
      enable = true;
      settings.PermitRootLogin = "no";
      settings.PasswordAuthentication = false;
    };
  };

  security.sudo.wheelNeedsPassword = false;

  users.users.${username} = {
    name = username;
    home = "/home/${username}";
    isNormalUser = true;
    extraGroups = [ "wheel" "network" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFFeU4GXH+Ae00DipGGJN7uSqPJxWFmgRo9B+xjV3mK4" ];
    initialHashedPassword = "$y$j9T$aeZHaSe8QKeC0ruAi9TKo.$zooI/IZUwOupVDbMReaukiargPrF93H/wdR/.0zsrr.";
  };

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

  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    lshw
    dig
    busybox
  ];

  programs.zsh.enable = true;
  programs.zsh.histFile = "$HOME/.local/share/zsh_history";

  services.tailscale.enable = true;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

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

