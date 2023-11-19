{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, disko }:
    let
      username = "kghost";
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.deckard = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./machines/deckard/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useUserPackages = true;
              useGlobalPkgs = true;
              users.${username} = ./machines/deckard/home.nix;
              extraSpecialArgs = { inherit username; };
            };
          }
          disko.nixosModules.disko
        ];
        specialArgs = { inherit username; };
      };
    };
}
