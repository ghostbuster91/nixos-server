{ pkgs, username, inputs, ... }: {
  users.users.${username}.shell = pkgs.zsh;

  services.journald.extraConfig = "SystemMaxUse=100M";

  system.autoUpgrade = {
    enable = false;
    dates = "weekly";
    flake = inputs.self.outPath;
    flags = [
      "--update-input"
      "nixpkgs"
      "-L"
    ];
    allowReboot = true;
    rebootWindow = {
      lower = "02:00";
      upper = "04:00";
    };
  };

  programs = {
    zsh.enable = true;
    ssh.startAgent = true;
    command-not-found.enable = false;
  };

  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings = {
    extra-substituters = [ "https://cache.garnix.io" ];
    extra-trusted-public-keys = [ "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g=" ];
  };

  environment.systemPackages = with pkgs; [
    neovim
    git
    wget
    curl

    neofetch
    nnn
    bottom
    htop
    iotop
    iftop
    nmon

    strace
    ltrace
    lsof

    mtr
    iperf3
    nmap
    ldns
    aria2
    socat
    tcpdump
    ethtool
    dnsutils
    wavemon

    sysstat
    lm_sensors
    pciutils
    lshw

    zip
    xz
    unzip
    p7zip

    file
    which
    tree
    gnused
    gnutar
    gawk

    iw
  ];

  environment.variables.EDITOR = "nvim";
}
