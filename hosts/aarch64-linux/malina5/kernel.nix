{ pkgs, lib, ... }:
let
  kernelBundle = pkgs.linuxAndFirmware.v6_6_31;
in
{
  boot = {
    tmp.useTmpfs = true;
    loader.raspberryPi.firmwarePackage = kernelBundle.raspberrypifw;
    loader.raspberryPi.bootloader = "kernel";
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
