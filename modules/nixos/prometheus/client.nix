{ config, ... }: {

  networking.firewall = {
    interfaces."tailscale0" = {
      allowedTCPPorts = [
        config.services.prometheus.exporters.node.port
        config.services.prometheus.exporters.systemd.port
      ];
    };
  };
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        openFirewall = true;
        port = 9002;
      };
      systemd = {
        enable = true;
        port = 9003;
        openFirewall = true;
      };
    };
  };

}
