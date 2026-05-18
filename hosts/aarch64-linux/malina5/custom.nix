{ config, pkgs, ... }: {

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.release;

  boot.zfs = {
    devNodes = "/dev/disk/by-id";
  };
  time.timeZone = "UTC";
  networking.hostId = "8821e309"; # NOTE: for zfs, must be unique

  services.udev.extraRules = ''
    # Ignore partitions with "Required Partition" GPT partition attribute
    # On our RPis this is firmware (/boot/firmware) partition
    ENV{ID_PART_ENTRY_SCHEME}=="gpt", \
      ENV{ID_PART_ENTRY_FLAGS}=="0x1", \
      ENV{UDISKS_IGNORE}="1"
  '';

  system.nixos.tags =
    let
      cfg = config.boot.loader.raspberryPi;
    in
    [
      "raspberry-pi-${cfg.variant}"
      cfg.bootloader
      config.boot.kernelPackages.kernel.version
    ];

  nix.settings = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  services.tailscale.enable = true;

  # Mirrors nixpkgs commit b9c75a3094f0 — psycopg's `slow`-marked tests have
  # timing-sensitive SIGALRM assertions that race on slower aarch64 builders
  # (upstream psycopg#883). Remove once nixpkgs is bumped past that commit.
  nixpkgs.overlays = [
    (_final: prev: {
      python313 = prev.python313.override {
        packageOverrides = _pyfinal: pyprev: {
          psycopg = pyprev.psycopg.overridePythonAttrs (old: {
            disabledTestMarks = (old.disabledTestMarks or [ ]) ++ [ "slow" ];
          });
        };
      };
    })
  ];
}
