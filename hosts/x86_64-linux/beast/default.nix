{ inputs, username, ... }:
{
  nixpkgs.hostPlatform = "x86_64-linux";
  imports =
    [
      ./backup.nix
      ./custom.nix
      ./attic-pusher.nix
      ./whisper.nix
      inputs.disko.nixosModules.default
      (import ./disko-config.nix {
        disks = [ "/dev/nvme0n1" ];
      })
      ./impermanence.nix
      ./nvidia.nix
      inputs.impermanence.nixosModules.impermanence
      inputs.home-manager.nixosModules.home-manager
      inputs.agenix.nixosModules.default
      inputs.self.nixosModules.ssh
      inputs.self.nixosModules.nix
      inputs.self.nixosModules.attic-watch-store
      inputs.self.nixosModules.nix-remote-builder
      {
        services.nix-remote-builder = {
          enable = true;
          authorizedKeys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHCRRt2uAKj46yJ61AjOJSFSXGzleSxbLsjr5f32F9Z/ root@focus"
          ];
        };
      }
      inputs.self.nixosModules.impermanence
      inputs.self.nixosModules.system-user
      inputs.nix-index-database.nixosModules.nix-index
      inputs.nixos-facter-modules.nixosModules.facter
      {
        config.facter.reportPath =
          if builtins.pathExists ./facter.json then
            ./facter.json
          else
            throw "Have you forgotten to run nixos-anywhere with `--generate-hardware-config nixos-facter ./facter.json`?";
      }
      inputs.self.nixosModules.backup
      {
        config.homelab.hostname = "beast";
      }
      inputs.self.nixosModules.meta
      inputs.self.nixosModules.proxy
      inputs.self.nixosModules.oauth2
      inputs.self.nixosModules.oauth2-proxy
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
