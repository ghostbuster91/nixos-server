{ config, lib, pkgs, ... }:
let
  cfg = config.services.nix-remote-builder;
in
{
  options.services.nix-remote-builder = {
    enable = lib.mkEnableOption "dedicated nix-daemon SSH user for accepting remote builds";
    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys allowed to log in as the nix-remote-builder user.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.nix-remote-builder = {
      isNormalUser = true;
      description = "Nix remote builder";
      home = "/var/lib/nix-remote-builder";
      createHome = true;
      shell = pkgs.bash;
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };
    nix.settings.trusted-users = [ "nix-remote-builder" ];
  };
}
