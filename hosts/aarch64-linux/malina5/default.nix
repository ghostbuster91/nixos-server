{ inputs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  imports =
    [
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      inputs.agenix.nixosModules.default
      # Hardware configuration
      ./hw.nix
      ./disko-nvme-zfs.nix
      ./impermanence.nix
      ./kernel.nix
      ./network.nix
      # Further user configuration
      ./custom.nix
      ./nice-looking-console.nix
      ./backup.nix
      ./attic.nix
      inputs.self.nixosModules.impermanence
      inputs.self.nixosModules.zfs
      inputs.self.nixosModules.system-user
      inputs.self.nixosModules.ssh
      inputs.self.nixosModules.backup
      inputs.self.nixosModules.nix
      # Homelab
      inputs.self.nixosModules.proxy
      inputs.self.nixosModules.zigbee2mqtt
      inputs.self.nixosModules.ha
      inputs.self.nixosModules.mosquitto
      inputs.self.nixosModules.meta
    ];
}
