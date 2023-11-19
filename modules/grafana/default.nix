{ config, pkgs, ... }: {
  # grafana configuration
  services.grafana = {
    enable = true;
    settings = {
      server = {
        # Listening Address
        http_addr = "127.0.0.1";
        # and Port
        http_port = 3000;
        # Grafana needs to know on which domain and URL it's running
        domain = "deckard.lan";
      };
    };
  };

  services.nginx.virtualHosts."your.domain" = {
    addSSL = true;
    enableACME = true;
    locations."/grafana/" = {
      proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}/";
      proxyWebsockets = true;
    };
  };
}
