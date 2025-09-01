{ lib, config, ... }: {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  networking = {
    nameservers = [
      "8.8.8.8"
    ];
    defaultGateway = "172.31.1.1";
    defaultGateway6 = {
      address = "fe80::1";
      interface = "eth0";
    };
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      inherit (config.homelab.vps.interfaces) eth0;
    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="92:00:06:6c:73:b1", NAME="eth0"

  '';
}


