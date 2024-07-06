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
  systemd.services.nginx.serviceConfig.ProtectHome = false;
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
        sslCertificate = "/var/nginx-selfsigned.crt";
        sslCertificateKey = "/var/nginx-selfsigned.key";
        forceSSL = true;

        locations."/" = {
          proxyPass = "http://esphome";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header    X-Real-IP           $remote_addr;
            proxy_set_header    X-Forwarded-For     $proxy_add_x_forwarded_for;
            proxy_set_header    X-Forwarded-Proto   $scheme;
            proxy_set_header    Host                $host;
            proxy_set_header    X-Forwarded-Host    $host;
            proxy_set_header    X-Forwarded-Port    $server_port;
          '';
        };
      };
    };
  };
}
