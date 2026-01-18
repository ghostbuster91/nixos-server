({ inputs, ... }: {
  imports = with inputs.nixos-raspberrypi.nixosModules; [
    # Hardware configuration
    raspberry-pi-5.base
    raspberry-pi-5.page-size-16k
    raspberry-pi-5.display-vc4
    ./pi5-configtxt.nix
  ];
})
