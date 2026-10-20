{ config
, pkgs
, ...
}: {
  boot.supportedFilesystems = [ "zfs" ];
  # boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  # The root pool should never be imported forcefully.
  # Failure to import is important to notice!
  boot.zfs.forceImportRoot = false;

  environment.systemPackages = with pkgs; [ zfs ];

  services.zfs = {
    autoScrub = {
      enable = true;
      interval = "weekly";
    };
    trim = {
      enable = true;
      interval = "weekly";
    };
  };

  # services.telegraf.extraConfig.inputs = lib.mkIf config.services.telegraf.enable {
  #   zfs.poolMetrics = true;
  # };

  services.prometheus.exporters = {
    zfs = {
      enable = true;
      port = 9004;

      # `openFirewall` is deliberately off: it renders an *unscoped*
      # `ip46tables -A nixos-fw -p tcp --dport 9004` (via extraCommands, not
      # allowedTCPPorts), accepting on every interface including the LAN. The
      # interface-scoped rule below is what we want -- prometheus reaches every
      # exporter as `<host>.tail.<domain>` over the tailnet. Same reasoning as
      # prometheus/client.nix and smartctl.nix.
      openFirewall = false;
    };
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    config.services.prometheus.exporters.zfs.port
  ];

  # Roll the root dataset back to a pristine snapshot on every boot (impermanence).
  # systemd stage-1 (the default for ZFS hosts since 25.11/26.05) does not support
  # boot.initrd.postMountCommands, so this runs as an initrd service ordered after
  # the pool import and before the root filesystem is mounted.
  boot.initrd.systemd.services.rollback-root = {
    description = "Rollback root ZFS dataset to a pristine state on boot";
    wantedBy = [ "initrd.target" ];
    after = [ "zfs-import-rpool1.service" ];
    before = [ "sysroot.mount" ];
    path = [ pkgs.zfs ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r rpool1/local/root@blank
    '';
  };
}
