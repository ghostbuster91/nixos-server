{ lib, ... }: {
  imports = [
    ./grafana
    ./prometheus
    ./loki
    ./esphome
    ./avahi
    ./ha
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
