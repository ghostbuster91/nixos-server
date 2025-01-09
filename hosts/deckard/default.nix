{ inputs, username, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  imports =
    [
      ./custom.nix
      ./hardware-configuration.nix
      inputs.disko.nixosModules.default
      (import ./disko-config.nix {
        disks = [ "/dev/sda" ];
      })
      ./impermanence.nix
      inputs.impermanence.nixosModules.impermanence
      inputs.self.nixosModules.grafana
      inputs.self.nixosModules.prometheus
      inputs.self.nixosModules.loki
      inputs.self.nixosModules.esphome
      inputs.self.nixosModules.avahi
      inputs.self.nixosModules.ha
      inputs.home-manager.nixosModule
      inputs.nix-index-database.nixosModules.nix-index
      {
        config.homelab.domain = "local";
      }
      inputs.self.nixosModules.meta
      inputs.agenix.nixosModules.default
      inputs.self.nixosModules.zfs
    ];

  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    users.${username} = {
      imports = [
        inputs.self.homeModules.base
        inputs.self.homeModules.nvim
        inputs.self.homeModules.zsh
        inputs.self.homeModules.git
      ];
    };
    extraSpecialArgs = { inherit username; };
  };

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It’s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
