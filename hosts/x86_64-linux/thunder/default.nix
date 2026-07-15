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
      ./mattermost.nix
      ./cloudflare-tunnel.nix
      ./dashy.nix
      ./vaultwarden.nix
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
      inputs.self.nixosModules.logs-alloy
      inputs.self.nixosModules.prometheus-client
      inputs.self.nixosModules.ssh
      inputs.self.nixosModules.nix
      inputs.self.nixosModules.impermanence
      inputs.self.nixosModules.system-user
      inputs.nix-index-database.nixosModules.nix-index
      inputs.self.nixosModules.kanidm
      # oauth2-proxy runs locally so nginx's auth_request for the protected
      # homepage vhost hits a local socket. thunder also hosts the oauth2.<domain>
      # login portal (see dns.nix) — co-located with kanidm, so the full login
      # flow is beast-independent. Shares the cookie secret + web-sentinel client
      # with beast (secrets.nix recipients); the cookie is scoped to .ext-domain
      # so a single login works across every host.
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
