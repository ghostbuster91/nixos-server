{ lib, ... }: {
  imports = [
    ./grafana
    ./prometheus
    ./loki
    ./esphome
    ./avahi
  ];

  options = with lib; {
    homelab.domain = mkOption {
      type = types.str;
    };
  };

  config = {
    homelab.domain = "local";
  };
}
