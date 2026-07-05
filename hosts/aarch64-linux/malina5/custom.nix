{ config, ... }: {

  # We are stateless, so just default to latest.
  system.stateVersion = config.system.nixos.release;

  boot.zfs = {
    devNodes = "/dev/disk/by-id";
  };

  # Memory headroom so heavy aarch64 compiles don't get OOM-killed — this box is
  # the homelab's only aarch64 remote builder (see nix-remote-builder above) yet
  # only has 8 GB and also runs Home Assistant, atticd, etc. Two levers:
  #  - Cap ZFS ARC. By default it grows toward all-but-1GB (~6.85 GiB here),
  #    expanding into the RAM that parallel cc1plus needs, and it doesn't shrink
  #    fast enough under an allocation spike, so the OOM killer fires first (it
  #    killed a dart build on 2026-07-07). Pin it to 2 GiB for deterministic
  #    headroom.
  #  - zram. Compressed (zstd) RAM swap as a cushion for the remaining spikes;
  #    far faster than disk swap and avoids swap-on-ZFS deadlocks.
  boot.kernelParams = [ "zfs.zfs_arc_max=2147483648" ]; # 2 GiB
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  time.timeZone = "Europe/Warsaw";
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
      cfg = config.boot.loader.raspberry-pi;
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
  #
  # django's test_crafted_xml_performance asserts a serialization speedup factor
  # ≤ 2 but gets ~3 on loaded aarch64 builders. Same class of flaky timing test.
  # Remove once nixpkgs skips this test upstream.
  nixpkgs.overlays = [
    (_final: prev: {
      python313 = prev.python313.override {
        packageOverrides = _pyfinal: pyprev: {
          psycopg = pyprev.psycopg.overridePythonAttrs (old: {
            disabledTestMarks = (old.disabledTestMarks or [ ]) ++ [ "slow" ];
          });
          django = pyprev.django.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace tests/serializers/test_xml.py \
                --replace-fail "test_crafted_xml_performance" "dont_test_crafted_xml_performance"
            '';
          });
        };
      };
      # Home Assistant is on python 3.14 here. aiobotocore's test suite pulls
      # moto -> cfn-lint -> aws-sam-translator, which nixpkgs marks unsupported
      # on 3.14, breaking eval of the aws_s3 component. We don't run these tests,
      # so drop the check inputs. Remove once the closure supports 3.14.
      python314 = prev.python314.override {
        packageOverrides = _pyfinal: pyprev: {
          aiobotocore = pyprev.aiobotocore.overridePythonAttrs (_old: {
            doCheck = false;
            nativeCheckInputs = [ ];
          });
        };
      };
    })
  ];
}
