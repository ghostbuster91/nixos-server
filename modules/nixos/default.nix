{
  flake.nixosModules = {
    grafana = ./grafana;
    prometheus-server = ./prometheus/server.nix;
    prometheus-client = ./prometheus/client.nix;
    logs-loki = ./logs/loki.nix;
    logs-promtail = ./logs/promtail.nix;
    esphome = ./esphome;
    avahi = ./avahi;
    ha = ./ha;
    meta = ./meta.nix;
    zfs = ./zfs.nix;
  };

}
