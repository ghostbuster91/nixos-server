{ config, pkgs-unstable, ... }:
let
  roleName = "esphome";
in
{

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/private/esphome";
      mode = "0700";
    }
  ];
  # options = with lib; {
  #   homelab.domain = mkOption {
  #     type = types.str;
  #   };
  # };

  # copied from https://sourcegraph.com/github.com/oddlama/nix-config@e1e8997525624b2184a80d6277b0d2a0af818af3/-/blob/hosts/zackbiene/esphome.nix
  services.esphome = {
    enable = true;
    enableUnixSocket = true;
    package = pkgs-unstable.esphome;
  };

  systemd.services.nginx = {
    serviceConfig.SupplementaryGroups = [ "esphome" ];
    requires = [ "esphome.service" ];
  };

  networking.firewall = {
    allowedUDPPorts = [
      5353 # mDNS for esphome
    ];
  };
  # systemd.services.nginx.serviceConfig.ProtectHome = false;
  services = {
    nginx = {
      upstreams."esphome" = {
        servers."unix:/run/esphome/esphome.sock" = { };
        extraConfig = ''
          zone esphome 64k;
          keepalive 2;
        '';
      };
      virtualHosts."${roleName}.${config.homelab.domain}" = {
        serverName = "${roleName}.${config.homelab.domain}";
        sslCertificate = config.age.secrets."nginx-selfsigned.cert".path;
        sslCertificateKey = config.age.secrets."nginx-selfsigned.key".path;
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://esphome";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };
}
