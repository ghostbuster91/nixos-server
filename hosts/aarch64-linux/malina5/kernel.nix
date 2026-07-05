{ pkgs, lib, ... }:
let
  kernelBundle = pkgs.linuxAndFirmware.v6_6_31;
in
{
  boot = {
    tmp.useTmpfs = true;
    # nixos-raspberrypi reimplements the (now-removed upstream) raspberryPi
    # loader options under the hyphenated `boot.loader.raspberry-pi` namespace.
    # We only override the firmware to keep it matched to the pinned v6_6_31
    # kernel below; the bootloader type is left at the board default
    # (`kernelboot`, from raspberry-pi-5.base) so a switch doesn't change how
    # this live Pi boots.
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
