{ config, pkgs, ... }: {

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.release;

  boot.zfs = {
    devNodes = "/dev/disk/by-id";
  };
  time.timeZone = "UTC";
  networking.hostId = "8821e309"; # NOTE: for zfs, must be unique

  services.udev.extraRules = ''
    # Ignore partitions with "Required Partition" GPT partition attribute
    # On our RPis this is firmware (/boot/firmware) partition
    ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
      ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
      ENV{UDISKS_IGNORE}="1"
  '';

  environment.systemPackages = with pkgs; [
    tree
    vim
  ];

  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberryPi;
    in
    [
      "raspberry-pi-${cfg.variant}"
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];

  services.tailscale.enable = true;
}
