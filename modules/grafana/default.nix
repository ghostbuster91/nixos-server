{ config, pkgs, ... }: {
  # grafana configuration
  services.grafana = {
    enable = true;
    settings = {
      server = {
        # Listening Address
        # http_addr = "127.0.0.1";
        http_addr = "0.0.0.0";
        # and Port
        http_port = 3000;
        # Grafana needs to know on which domain and URL it's running
        # domain = "deckard.lan";
        # root_url = "http://deckard.lan/";
      };
    };
  };

  services.nginx.enable = true;
  services.nginx.virtualHosts."deckard.lan" = {
    addSSL = false;
    enableACME = false;
    locations."/grafana/" = {
      proxyPass = "http://${toString config.services.grafana.settings.server.http_addr}:${toString config.services.grafana.settings.server.http_port}/";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
      '';
    };
    locations."/prometheus/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.prometheus.port}/";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host;
      '';
    };
  };
  # security.acme = {
  #   acceptTerms = true;
  #   defaults.email = "foo@bar.com";
  # };
}
