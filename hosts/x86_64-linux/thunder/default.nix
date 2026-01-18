{ inputs, username, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  imports =
    [
      ./custom.nix
      ./backup.nix
      ./hardware-configuration.nix
      ./networking.nix # generated at runtime by nixos-infect
      ./topology.nix
      ./headscale.nix
      ./dns.nix
      ./blog.nix
      inputs.disko.nixosModules.default
      (import ./disko-config.nix {
        disks = [ "/dev/sda" ];
      })
      inputs.self.nixosModules.meta
      ./impermanence.nix
      inputs.impermanence.nixosModules.impermanence
      inputs.nix-topology.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.agenix.nixosModules.default
      inputs.self.nixosModules.proxy
      inputs.self.nixosModules.meta
      inputs.self.nixosModules.backup
      inputs.self.nixosModules.logs-promtail
      inputs.self.nixosModules.prometheus-client
      inputs.self.nixosModules.ssh
      inputs.self.nixosModules.nix
      inputs.self.nixosModules.impermanence
      inputs.self.nixosModules.system-user
    ];

  home-manager = {
    useUserPackages = true;
    useGlobalPkgs = true;
    users.${username} = {
      imports = [
        inputs.self.homeModules.base
        inputs.self.homeModules.zsh
        inputs.self.homeModules.git
      ];
    };
    extraSpecialArgs = { inherit username; };
  };
}
