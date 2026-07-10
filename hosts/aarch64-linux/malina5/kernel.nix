{ pkgs, lib, ... }:
let
  kernelBundle = pkgs.linuxAndFirmware.v6_12_87;
in
{
  boot = {
    tmp.useTmpfs = true;
    # nixos-raspberrypi reimplements the (now-removed upstream) raspberryPi
    # loader options under the hyphenated `boot.loader.raspberry-pi` namespace.
    # We override the firmware to keep it matched to the pinned v6_6_31 kernel
    # below.
    #
    # Bootloader is the new generational `kernel` (was the legacy `kernelboot`,
    # now deprecated by nixos-raspberrypi). Each generation gets its own
    # kernel/initrd/DTBs under /boot/firmware/nixos/<gen>/ and config.txt is
    # given an os_prefix pointing at the active one; DTBs come from the
    # generation's kernel (useGenerationDeviceTree defaults to true here).
    loader.raspberry-pi.bootloader = "kernel";
    loader.raspberry-pi.firmwarePackage = kernelBundle.raspberrypifw;
    kernelPackages = kernelBundle.linuxPackages_rpi5;
  };

  nixpkgs.overlays = lib.mkAfter [
    (_self: _super: {
      # This is used in (modulesPath + "/hardware/all-firmware.nix") when at least 
      # enableRedistributableFirmware is enabled
      # I know no easier way to override this package
      inherit (kernelBundle) raspberrypiWirelessFirmware;
      # Some derivations want to use it as an input,
      # e.g. raspberrypi-dtbs, omxplayer, sd-image-* modules
      inherit (kernelBundle) raspberrypifw;
    })
  ];
}
