{ pkgs, config, ... }:
{
  environment.persistence."/persist" = {
    directories = [
      {
        directory = "/var/lib/mattermost";
        mode = "0750";
        user = "mattermost";
        group = "mattermost";
      }
      {
        directory = "/var/lib/postgresql/${config.services.postgresql.package.psqlSchema}";
        mode = "0700";
        user = "postgres";
        group = "postgres";
      }
    ];
  };

  services.cloudflared = {
    tunnels = {
      "blog-tunnel" = {
        ingress = {
          "mattermost.${config.homelab.ext-domain}" = "http://localhost:${toString config.services.mattermost.port}";
        };
      };
    };
  };

  services.mattermost = {
    enable = true;
    siteUrl = "https://mattermost.${config.homelab.ext-domain}";
    preferNixConfig = true;
    settings = {
      TeamSettings.EnableOpenServer = false;
    };
    plugins = [
      (pkgs.fetchurl {
        url = "https://github.com/mattermost/mattermost-plugin-calls/releases/download/v1.11.5/mattermost-plugin-calls-v1.11.5.tar.gz";
        hash = "sha256-YCcF3mA0e5DM4hQUo5kyvficna7Wa1Szk+bfM19zA1o=";
      })
    ];
  };
}
