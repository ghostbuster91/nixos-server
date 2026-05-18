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

  users.users.${username} = {
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  programs.zsh.histFile = "$HOME/.local/share/zsh_history";

  services.tailscale.enable = true;

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

