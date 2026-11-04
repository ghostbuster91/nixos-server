_: {
  topology.self = {
    hardware.info = "Raspberry Pi 5 Model B · 8 GiB RAM · Samsung 980 500 GB NVMe";

    # end0 has to be declared by hand: malina5 uses networkd's stock
    # `99-ethernet-default-dhcp` network, whose `Name = "en*"` is a wildcard, so
    # the systemd-network extractor cannot derive an interface name from it.
    # Address comes from the FunBox over DHCP, hence no literal here.
    interfaces.end0 = {
      type = "ethernet";
      addresses = [ "DHCP" ];
    };
  };
}
