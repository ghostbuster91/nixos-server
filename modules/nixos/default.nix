{
  flake.nixosModules = {
    grafana = ./grafana;
    prometheus = ./prometheus;
    loki = ./loki;
    esphome = ./esphome;
    avahi = ./avahi;
    ha = ./ha;
    meta = ./meta.nix;
    zfs = ./zfs.nix;
  };

}
