{ pkgs, username, ... }: {

  zramSwap.enable = true;

  networking.hostName = "thunder";
  networking.hostId = "5ada2fab";

  programs.zsh.enable = true;
  programs.zsh.histFile = "$HOME/.local/share/zsh_history";

  services.tailscale.enable = true;
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  users.users.${username} = {
    shell = pkgs.zsh;
  };

  services.fail2ban.enable = true;
  security.apparmor = {
    enable = true;
    packages = [ pkgs.apparmor-profiles ];
    killUnconfinedConfinables = false;
  };

  system.stateVersion = "25.05";
}
