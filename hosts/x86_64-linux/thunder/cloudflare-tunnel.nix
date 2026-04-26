{ config, username, ... }:
{
  age.secrets.cloudflared-tunnel = {
    file = ../../../secrets/cloudflared-tunnel.age;
    mode = "600";
    owner = username;
  };

  services.cloudflared = {
    enable = true;
    tunnels = {
      "blog-tunnel" = {
        credentialsFile = config.age.secrets.cloudflared-tunnel.path;
        default = "http_status:404";
      };
    };
  };
}
