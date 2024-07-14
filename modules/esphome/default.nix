{ config, pkgs-unstable, ... }:
let
  roleName = "esphome";
in
{
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
  systemd.services.nginx.serviceConfig.ProtectHome = false;
  services = {
    nginx = {
      commonHttpConfig = ''
        # needed for github proxy
        large_client_header_buffers 4 16k;
        client_body_buffer_size 128k;
      '';
      resolver.addresses = [ "8.8.8.8" ];
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
      virtualHosts."${roleName}-firmware.${config.homelab.domain}" = {
        serverName = "${roleName}-firmware.${config.homelab.domain}";
        forceSSL = false;

        locations."/" = {
          proxyPass = "https://github.com";
          extraConfig = ''
            proxy_buffers 8 16k;
            proxy_buffer_size 16k;
            proxy_busy_buffers_size 24k;

            proxy_redirect https://github.com http://esphome-firmware.local;
          '';
        };
      };
    };
  };
}
