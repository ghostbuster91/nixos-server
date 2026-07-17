{ config, ... }:
let
  port = 8083;
  domain = "pdf.${config.homelab.ext-domain}";
in
{
  services.stirling-pdf = {
    enable = true;
    environment = {
      # Bind loopback only; nginx terminates TLS and gates access.
      SERVER_ADDRESS = "127.0.0.1";
      SERVER_PORT = port;
      # Keep Stirling's own login system OFF (its default). Access is gated
      # entirely by oauth2-proxy in front of nginx (see the vhost below), so
      # Stirling runs anonymous — no account database, no default admin user.
      # Native OIDC is deliberately avoided: free-tier Stirling paywalls OAuth
      # user auto-provisioning and offers no way to disable its built-in admin
      # login, so the reverse-proxy gate is the clean way to put it behind kanidm.
      SECURITY_ENABLELOGIN = false;
    };
  };

  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    # Gate behind oauth2-proxy (already running on beast for chat/comfyui).
    # access_stirling is emitted by kanidm's web-sentinel client for members of
    # the web-sentinel.stirling group.
    oauth2 = {
      enable = true;
      allowedGroups = [ "access_stirling" ];
    };
    extraConfig = ''
      client_max_body_size 256M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
