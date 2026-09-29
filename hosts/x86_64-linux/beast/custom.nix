{ pkgs, username, config, ... }:
{

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  time.timeZone = "Europe/Warsaw";

  # Compressed RAM-backed swap. Avoids swap-on-zvol deadlocks (all disks here
  # are ZFS) while giving OOM headroom for the memory-hungry AI workloads.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  networking = {
    hostName = "beast"; # Define your hostname.
    hostId = "11fb3862";
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

  age.secrets.beast-tailscale-key = {
    file = ../../../secrets/beast-tailscale-key.age;
    mode = "600";
    owner = username;
  };
  services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.beast-tailscale-key.path;
    extraUpFlags = [ "--advertise-tags=tag:ai,tag:workstation" "--login-server=https://headscale.${config.homelab.sec-domain}" ];
  };

  system.stateVersion = "25.11";
}

