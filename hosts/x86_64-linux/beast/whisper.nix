{ ... }:
{
  nixpkgs.config.cudaSupport = true;

  nix.settings = {
    extra-substituters = [
      "https://cuda-maintainers.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  services.wyoming.faster-whisper.servers.pl = {
    enable = true;
    model = "turbo";
    language = "pl";
    device = "cuda";
    beamSize = 1;
    uri = "tcp://0.0.0.0:10300";
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 10300 ];

  # DynamicUser=true on the unit means the model cache lands under
  # /var/lib/private/wyoming/faster-whisper; persisting that path avoids
  # re-downloading the ~1.6 GB turbo model after every impermanence rollback.
  environment.persistence."/state".directories = [
    {
      directory = "/var/lib/private/wyoming/faster-whisper";
      mode = "0700";
    }
  ];
}
