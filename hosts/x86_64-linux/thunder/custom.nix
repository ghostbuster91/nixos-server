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
    extraUpFlags = [ "--advertise-tags=tag:auth" "--login-server=https://headscale.${config.homelab.sec-domain}" ];
  };
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  users.users.${username} = {
    shell = pkgs.zsh;
  };

  environment.systemPackages = with pkgs; [
    jq
    vim
    git
    wget
    lshw
    dig
    busybox
    curl
  ];


  services.fail2ban.enable = true;
  security.apparmor = {
    enable = true;
    packages = [ pkgs.apparmor-profiles ];
    killUnconfinedConfinables = false;
  };

  system.stateVersion = "25.05";
}
