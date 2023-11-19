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
        root_url = "https://deckard.lan/grafana/";
      };
    };
  };
<<<<<<< Updated upstream

  services.nginx.virtualHosts."deckard.lan" = {
||||||| Stash base

  services.nginx.virtualHosts."your.domain" = {
=======
  services.nginx.enable = true;
  services.nginx.virtualHosts."your.domain" = {
>>>>>>> Stashed changes
    addSSL = true;
    enableACME = true;
    locations."/grafana/" = {
      proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}/";
      proxyWebsockets = true;
    };
  };
  security.acme = {
    acceptTerms = true;
    defaults.email = "foo@bar.com";
  };
}
