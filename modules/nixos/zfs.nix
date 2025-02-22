{ lib
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

  boot.initrd.postDeviceCommands = lib.mkAfter ''
    zfs rollback -r rpool1/local/root@blank
  '';
}
