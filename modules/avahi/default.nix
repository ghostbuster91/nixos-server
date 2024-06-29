{ ... }: {

  networking.firewall = {
    allowedUDPPorts = [
      5353
    ];
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      userServices = true;
    };
  };
}
