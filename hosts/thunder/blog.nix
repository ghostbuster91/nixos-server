{ config, username, inputs, ... }:
let
  localPort = 8333;
in
{
  age.secrets.cloudflared-tunnel = {
    file = ../../secrets/cloudflared-tunnel.age;
    mode = "600";
    owner = username;
  };

  services.cloudflared = {
    enable = true;
    tunnels = {
      "blog-tunnel" = {
        credentialsFile = config.age.secrets.cloudflared-tunnel.path;
        default = "http_status:404";
        ingress = {
          "blog.${config.homelab.ext-domain}" = "http://localhost:${toString localPort}";
        };
      };
    };
  };

  services.nginx =
    let
      commonHeaders = ''
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "geolocation=(), microphone=()" always;

        add_header X-Robots-Tag "noai, noimageai" always;
      '';
    in
    {
      enable = true;
      virtualHosts."blog.local" = {
        root = "${inputs.ghostbuster91-blog.packages."x86_64-linux".website}";
        listen = [{ addr = "127.0.0.1"; port = localPort; }];

        extraConfig = ''
          if ($http_user_agent ~* "(GPTBot|ClaudeBot|Claude-User|Claude-SearchBot|PerplexityBot|CCBot|Google-Extended)") { return 403; }
          try_files $uri $uri/ =404;
        '';

        locations."/".extraConfig = ''
          add_header Cache-Control "no-cache";
        '' + commonHeaders;
        locations."~* \.(js|css|png|jpg|jpeg|gif|svg|ico|woff2?)$".extraConfig = ''
          add_header Cache-Control "public, max-age=31536000, immutable";
        '' + commonHeaders;
      };
    };
}
