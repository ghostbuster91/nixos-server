{ inputs, username, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";

  imports = [
    inputs.agenix.nixosModules.default
    ./secrets.nix
    ./custom.nix
    ./network.nix
    ./hostapd.nix
    ./monitoring.nix
    inputs.self.nixosModules.nix
    inputs.self.nixosModules.meta
    inputs.self.nixosModules.attic-cache
    inputs.self.nixosModules.ssh
    inputs.self.nixosModules.system-user
    inputs.self.nixosModules.rpi-builder
    inputs.self.nixosModules.logs-alloy
    inputs.home-manager.nixosModules.home-manager
    inputs.nix-index-database.nixosModules.nix-index

    inputs.nixos-sbc.nixosModules.default
    inputs.nixos-sbc.nixosModules.boards.bananapi.bpir3
    {
      sbc = {
        version = "0.3";
        bootstrap.rootFilesystem = "ext4";
        wireless.wifi.acceptRegulatoryResponsibility = true;
        # Surfer boots from SD (ext4) and has no NVMe/PCIe device, so the bpir3
        # cold-boot PCIe rescan is a no-op here. Disable it to avoid the
        # systemd-stage-1 `preDeviceCommands` assertion (26.05 defaults
        # boot.initrd.systemd.enable = true).
        board.bananapi.bpir3.pcieFixup = false;
      };
    }
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

  system.stateVersion = "24.05";
}
