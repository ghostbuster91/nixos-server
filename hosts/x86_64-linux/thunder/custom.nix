{ pkgs, username, config, ... }: {

  zramSwap.enable = true;

  networking.hostName = "thunder";
  networking.hostId = "5ada2fab";

  programs.zsh.enable = true;
  programs.zsh.histFile = "$HOME/.local/share/zsh_history";

  age.secrets.thunder-tailscale-key = {
    file = ../../../secrets/thunder-tailscale-key.age;
    mode = "600";
    owner = username;
  };
  services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.thunder-tailscale-key.path;
    # "server" enables net.ipv4.ip_forward + IPv6 forwarding sysctls, required
    # to route traffic as an exit node.
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--advertise-tags=tag:auth"
      "--advertise-exit-node"
      "--login-server=https://headscale.${config.homelab.sec-domain}"
    ];
  };

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
