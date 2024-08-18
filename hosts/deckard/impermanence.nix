{ lib, config, ... }:
let
  inherit
    (lib)
    mkOption
    optionals
    types
    ;
in
{
  # Give agenix access to the hostkey independent of impermanence activation
  age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # Expose a home manager module for each user that allows extending
  # environment.persistence.${sourceDir}.users.${userName} simply by
  # specifying home.persistence.${sourceDir} in home manager.
  home-manager.sharedModules = [
    {
      options.home.persistence = mkOption {
        description = "Additional persistence config for the given source path";
        default = { };
        type = types.attrsOf (types.submodule {
          options = {
            files = mkOption {
              description = "Additional files to persist via NixOS impermanence.";
              type = types.listOf (types.either types.attrs types.str);
              default = [ ];
            };

            directories = mkOption {
              description = "Additional directories to persist via NixOS impermanence.";
              type = types.listOf (types.either types.attrs types.str);
              default = [ ];
            };
          };
        });
      };
    }
  ];

  # State that should be kept across reboots, but is otherwise
  # NOT important information in any way that needs to be backed up.
  # fileSystems."/state".neededForBoot = true;
  # environment.persistence."/state" = {
  #   hideMounts = true;
  #   directories =
  #     [
  #       "/var/lib/systemd"
  #       "/var/log"
  #       "/var/spool"
  #     ]
  #     ++ optionals config.networking.wireless.iwd.enable [
  #       {
  #         directory = "/var/lib/iwd";
  #         mode = "0700";
  #       }
  #     ];
  # };

  # State that should be kept forever, and backed up accordingly.
  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
      "/etc/machine-id"
      { file = "/var/keys/secret_file"; parentDirectory = { mode = "u=rwx,g=,o="; }; }
    ];
    directories = [
      "/var/log"
      "/var/lib/bluetooth"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/etc/NetworkManager/system-connections"
      { directory = "/var/lib/colord"; user = "colord"; group = "colord"; mode = "u=rwx,g=rx,o="; }
    ];
    # directories =
    #   [
    #     "/var/lib/nixos"
    #   ]
    #   ++ optionals config.security.acme.acceptTerms [
    #     {
    #       directory = "/var/lib/acme";
    #       user = "acme";
    #       group = "acme";
    #       mode = "0755";
    #     }
    #   ]
    #   ++ optionals config.services.printing.enable [
    #     {
    #       directory = "/var/lib/cups";
    #       mode = "0700";
    #     }
    #   ]
    #   ++ optionals config.services.postgresql.enable [
    #     {
    #       directory = "/var/lib/postgresql";
    #       user = "postgres";
    #       group = "postgres";
    #       mode = "0700";
    #     }
    #   ];
  };
}
