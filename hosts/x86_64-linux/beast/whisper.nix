{ pkgs, ... }:
let
  # CUDA is scoped to *only* the faster-whisper package rather than flipped on
  # globally. A global `nixpkgs.config.cudaSupport = true` makes every
  # CUDA-aware package in beast's set a cache miss and rebuilds it against the
  # full CUDA toolkit — most damagingly open-webui's nixpkgs torch, ballooning
  # the closure past 100 GB. faster-whisper's engine (CTranslate2) is the only
  # thing here that genuinely needs a source-level CUDA build; comfyui ships its
  # own pre-built CUDA torch wheels and ollama uses `ollama-cuda`, so neither
  # depends on this flag. We build wyoming-faster-whisper from a throwaway
  # nixpkgs instance with cudaSupport on and hand it to the service's `package`
  # option, leaving the rest of the system on the normal (CPU) cache.
  pkgsCuda = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
  };
in
{
  nix.settings = {
    extra-substituters = [
      "https://cuda-maintainers.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  services.wyoming.faster-whisper.package = pkgsCuda.wyoming-faster-whisper;

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
  environment.persistence."/data/local".directories = [
    {
      directory = "/var/lib/private/wyoming/faster-whisper";
      mode = "0700";
    }
  ];
}
