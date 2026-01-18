{ inputs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  imports =
    [
      inputs.disko.nixosModules.disko
      inputs.impermanence.nixosModules.impermanence
      ./hw.nix
      ./disko-nvme-zfs.nix
      ./impermanence.nix
      ./kernel.nix
      ./network.nix
      # Further user configuration
      ./custom.nix
      ./nice-looking-console.nix
      inputs.self.nixosModules.impermanence
      inputs.self.nixosModules.zfs
      inputs.self.nixosModules.system-user
      inputs.self.nixosModules.ssh
    ];
}
