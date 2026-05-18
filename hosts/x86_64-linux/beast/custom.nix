{ pkgs, username, config, ... }:
{

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  networking = {
    hostName = "beast"; # Define your hostname.
    hostId = "11fb3862";
    networkmanager.enable = true;
    firewall.allowedTCPPorts = [
      80
      443
    ];
  };

  users.users.${username} = {
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  programs.zsh.histFile = "$HOME/.local/share/zsh_history";

  age.secrets.beast-tailscale-key = {
    file = ../../../secrets/beast-tailscale-key.age;
    mode = "600";
    owner = username;
  };
  services.tailscale = {
    enable = true;
    authKeyFile = config.age.secrets.beast-tailscale-key.path;
    extraUpFlags = [ "--advertise-tags=tag:ai" "--login-server=https://headscale.${config.homelab.sec-domain}" ];
  };

  environment.persistence."/state".directories = [
    {
      directory = "/var/lib/private/open-webui";
      mode = "0700";
    }
  ];

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
  };

  services.open-webui = {
    enable = true;
    host = "127.0.0.1";
    port = 11222;
    environment = {
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";

      ENABLE_COMMUNITY_SHARING = "False";
      ENABLE_ADMIN_EXPORT = "False";

      OLLAMA_BASE_URL = "http://localhost:${toString config.services.ollama.port}";
      TRANSFORMERS_CACHE = "/var/lib/open-webui/.cache/huggingface";

      WEBUI_AUTH = "False";
      ENABLE_SIGNUP = "False";
      WEBUI_AUTH_TRUSTED_EMAIL_HEADER = "X-Email";
      DEFAULT_USER_ROLE = "user";
    };
  };

  services.nginx =
    let
      roleName = "chat";
    in
    {
      upstreams.open-webui = {
        servers."127.0.0.1:${toString config.services.open-webui.port}" = { };
        extraConfig = ''
          zone open-webui 64k;
          keepalive 2;
        '';
        # monitoring = {
        #   enable = true;
        #   expectedBodyRegex = "Open WebUI";
        # };
      };
      virtualHosts."${roleName}.${config.homelab.ext-domain}" = {
        forceSSL = true;
        useACMEHost = config.homelab.ext-domain;
        oauth2 = {
          enable = true;
          allowedGroups = [ "access_openwebui" ];
          X-Email = "\${upstream_http_x_auth_request_preferred_username}@${config.homelab.ext-domain}";
        };
        extraConfig = ''
          client_max_body_size 128M;
        '';
        locations."/" = {
          proxyPass = "http://open-webui";
          proxyWebsockets = true;
          # X-Frame-Options = "SAMEORIGIN";
        };
      };
    };

  system.stateVersion = "25.11";
}

