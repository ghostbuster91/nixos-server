{lib, ...}:{
  imports = [
    ./grafana
    ./prometheus
    ./loki
  ];

  options = with lib; {
    homelab.domain = mkOption {
      type = types.str;
    # TODO: verify if this file build too many dependencies derivations
  };
  };

  config = {
    homelab.domain="lan";
  };
}
