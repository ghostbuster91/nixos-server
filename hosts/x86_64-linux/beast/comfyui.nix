{ inputs, config, pkgs, ... }:
{
  imports = [ inputs.comfyui-nix.nixosModules.default ];

  services.comfyui = {
    enable = true;
    enableManager = true;
    gpuSupport = "cuda";
    listenAddress = "127.0.0.1";
    port = 8188;
    dataDir = "/var/lib/comfyui";
    customNodes = {
      ComfyUI-Unload-Model = pkgs.fetchFromGitHub {
        owner = "SeanScripts";
        repo = "ComfyUI-Unload-Model";
        rev = "ac5ffb4ed05546545ce7cf38e7b69b5152714eed";
        hash = "sha256-+9W5howotJGOepoXSPHP8rGhs+FvAUHtK3ZtPMQ6Y/4=";
      };
    };
  };

  # Models live under dataDir and are large (~5-15GB per checkpoint) but
  # reproducibly redownloadable, so /data/local (not backed up) is the right tank.
  environment.persistence."/data/local".directories = [
    {
      directory = "/var/lib/comfyui";
      mode = "0750";
    }
  ];

  services.nginx = {
    upstreams.comfyui = {
      servers."127.0.0.1:${toString config.services.comfyui.port}" = { };
      extraConfig = ''
        zone comfyui 64k;
        keepalive 2;
      '';
    };
    virtualHosts."comfyui.${config.homelab.ext-domain}" = {
      forceSSL = true;
      useACMEHost = config.homelab.ext-domain;
      oauth2 = {
        enable = true;
        allowedGroups = [ "access_openwebui" ];
      };
      extraConfig = ''
        client_max_body_size 128M;
      '';
      locations."/" = {
        proxyPass = "http://comfyui";
        proxyWebsockets = true;
      };
    };
  };
}
