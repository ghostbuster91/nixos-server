{ inputs, ... }:
{
  imports = [ inputs.comfyui-nix.nixosModules.default ];

  services.comfyui = {
    enable = true;
    gpuSupport = "cuda";
    listenAddress = "127.0.0.1";
    port = 8188;
    dataDir = "/var/lib/comfyui";
  };

  # Models live under dataDir and are large (~5-15GB per checkpoint) but
  # reproducibly redownloadable, so /state (not backed up) is the right tank.
  environment.persistence."/state".directories = [
    {
      directory = "/var/lib/comfyui";
      mode = "0750";
    }
  ];
}
