_: {
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
