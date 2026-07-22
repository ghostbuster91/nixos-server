{ pkgs, username, config, ... }:
{

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  time.timeZone = "Europe/Warsaw";

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
    host = "0.0.0.0";
  };

  # ollama probes for GPUs once at startup and caches the result for the whole
  # process lifetime. If it starts before the nvidia driver is ready (e.g. during
  # a nixos-rebuild switch) it silently falls back to CPU forever. Block startup
  # until nvidia-smi succeeds so the CUDA backend is always picked up.
  systemd.services.ollama.serviceConfig.ExecStartPre =
    let
      wait-for-gpu = pkgs.writeShellScript "wait-for-nvidia-gpu" ''
        for i in $(seq 1 60); do
          ${config.hardware.nvidia.package.bin}/bin/nvidia-smi >/dev/null 2>&1 && exit 0
          sleep 1
        done
        echo "nvidia-smi never became ready; starting ollama anyway (CPU fallback likely)" >&2
        exit 0
      '';
    in
    "${wait-for-gpu}";

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ config.services.ollama.port ];

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

      HOME = "/var/lib/open-webui";
      OLLAMA_BASE_URL = "http://localhost:${toString config.services.ollama.port}";
      TRANSFORMERS_CACHE = "/var/lib/open-webui/.cache/huggingface";

      ENABLE_IMAGE_GENERATION = "True";
      IMAGE_GENERATION_ENGINE = "comfyui";
      COMFYUI_BASE_URL = "http://127.0.0.1:${toString config.services.comfyui.port}";

      WEBUI_AUTH = "False";
      ENABLE_SIGNUP = "False";
      WEBUI_AUTH_TRUSTED_EMAIL_HEADER = "X-Email";
      DEFAULT_USER_ROLE = "user";
    };
  };

  services.nginx = {
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
    virtualHosts."chat.${config.homelab.ext-domain}" = {
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

