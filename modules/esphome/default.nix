{ config, ... }:
let
  roleName = "esphome";
in
{
  # copied from https://sourcegraph.com/github.com/oddlama/nix-config@e1e8997525624b2184a80d6277b0d2a0af818af3/-/blob/hosts/zackbiene/esphome.nix
  services.esphome = {
    enable = true;
    enableUnixSocket = true;
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
        # Use wildcard domain
        # useACMEHost = config.homelab.domain;
        serverName = "${roleName}.${config.homelab.domain}";
        # sslCertificate = "/var/lib/acme/terenver.uk/full.pem";
        # sslCertificateKey = "/var/lib/acme/terenver.uk/key.pem";
        forceSSL = false;

        locations."/" = {
          proxyPass = "http://esphome";
          proxyWebsockets = true;
        };
      };
    };
  };
}
