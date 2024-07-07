{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, disko, nixpkgs-unstable }:
    let
      username = "kghost";
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
    in
    {
      nixosConfigurations.deckard = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./machines/deckard/configuration.nix
          ./modules
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
        specialArgs = {
          inherit username; inherit pkgs-unstable;
        };
      };
      formatter.${ system} = pkgs.nixpkgs-fmt;

    };
}
