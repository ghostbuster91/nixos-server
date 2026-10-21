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

  nixpkgs.overlays = [
    (_final: prev: {
      # buf is only a build-time tool here (pulled in by the mealie closure), and
      # this exact aarch64 output isn't on cache.nixos.org, so it compiles on the
      # Pi. Its checkPhase runs bufcheck tests that instantiate WASM plugins under
      # a context deadline; on this slow builder the module never instantiates in
      # time ("module closed with context deadline exceeded" in
      # TestRunBreakingPolicyLocal), failing the build. We don't ship buf's tests,
      # so drop the check. Remove once a cached aarch64 buf is available.
      buf = prev.buf.overrideAttrs (_old: {
        doCheck = false;
      });
      # deno (a runtime dep of mealie) isn't on cache.nixos.org for this aarch64
      # rev, so it compiles on the Pi. Its Cargo release profile forces
      # `lto = true` + `codegen-units = 1`, and with 4 build cores that runs
      # several whole-crate LTO rustc jobs at once, blowing past the Pi's 8 GB
      # (zram swap is RAM-backed, so it can't rescue this) — rustc gets
      # OOM-killed ("terminated by a deadly signal") compiling denort. cargo
      # honours these env vars over the Cargo.toml profile: turning LTO off and
      # splitting codegen units slashes peak memory. The binary is a bit larger/
      # slower, which is fine here. Remove once a cached aarch64 deno exists.
      deno = prev.deno.overrideAttrs (_old: {
        CARGO_PROFILE_RELEASE_LTO = "false";
        CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
      });
      # attic (atticd + the attic-client used by attic-watch-store) links nix's C++
      # libs, so it builds nixVersions.nix_2_28; this exact aarch64 nix 2.28.7 isn't
      # on cache.nixos.org, so it compiles on the Pi and runs nix's own unit tests.
      # The libstore RapidCheck property StorePathTest_RapidCheck.prop_check_regex_eq_parse
      # falsifies on random store-path names (e.g. "?/") from a parser/nameRegex
      # mismatch upstream — randomized, so effectively flaky. nix gates building the
      # unit-test subprojects on `-Dunit-tests`, which it hardcodes to true for any
      # natively-executable build (not on doCheck), so just setting doCheck=false
      # leaves the subprojects configured but drops rapidcheck/gtest, failing at
      # "rapidcheck not found". We don't ship nix's tests, so turn the subprojects
      # off entirely as well. Remove once a cached aarch64 nix_2_28 is available or
      # upstream fixes the property.
      nixVersions = prev.nixVersions // {
        nix_2_28 = prev.nixVersions.nix_2_28.overrideAttrs (old: {
          doCheck = false;
          doInstallCheck = false;
          mesonFlags =
            (builtins.filter (f: !prev.lib.hasPrefix "-Dunit-tests=" f) (old.mesonFlags or [ ]))
              ++ [ (prev.lib.mesonBool "unit-tests" false) ];
        });
      };
      # Mirrors nixpkgs commit b9c75a3094f0 — psycopg's `slow`-marked tests have
      # timing-sensitive SIGALRM assertions that race on slower aarch64 builders
      # (upstream psycopg#883). Remove once nixpkgs is bumped past that commit.
      #
      # django's test_crafted_xml_performance asserts a serialization speedup factor
      # ≤ 2 but gets ~3 on loaded aarch64 builders. Same class of flaky timing test.
      # Remove once nixpkgs skips this test upstream.
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
          # moto's stepfunctions idempotency test races on this slow aarch64
          # builder: the second create_state_machine call is expected to be a
          # no-op but the first execution hasn't settled, so it raises
          # ExecutionAlreadyExists. moto is a check input in the HA python 3.14
          # closure (via pycognito -> hass-nabucasa). Remove once nixpkgs skips
          # it upstream.
          moto = pyprev.moto.overridePythonAttrs (old: {
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_create_state_machine_twice_after_success"
            ];
          });
          # paho-mqtt (pulled into the HA 3.14 closure via aiomqtt) isn't cached for
          # this aarch64 rev, so it compiles on the Pi and runs its full pytest suite,
          # which drives real MQTT client subprocesses and a fake broker over sockets.
          # Several tests are timing-fragile on this slow builder — teardown SIGINTs
          # of helper clients (test_01_* family) and dropped callbacks (e.g.
          # test_client.py's on_disconnect never fires in time) — and it's whack-a-mole
          # to disable them one by one. pytestCheckHook ignores doCheck (it gates only
          # on dontUsePytestCheck), so skip the pytest phase outright; pythonImportsCheck
          # still verifies the module imports. Remove once a cached aarch64 paho-mqtt
          # is available.
          paho-mqtt = pyprev.paho-mqtt.overridePythonAttrs (_old: {
            dontUsePytestCheck = true;
          });
          # uvloop (a core Home Assistant dependency) isn't cached for this aarch64
          # rev, so it compiles on the Pi and runs its full pytest suite.
          # tests/test_regr1.py's test_issue39_regression spawns many concurrent
          # subprocess/loop cycles and asserts they all complete within a timeout,
          # failing with "deadlocked in libuv" on this slow, loaded builder — a
          # timing artifact, not a real deadlock (upstream has a history of this
          # test being flaky). Deselect just that test; the rest of the suite
          # (413 passing) still runs. Remove once a cached aarch64 uvloop exists.
          uvloop = pyprev.uvloop.overridePythonAttrs (old: {
            disabledTestPaths = (old.disabledTestPaths or [ ]) ++ [
              "tests/test_regr1.py::TestIssue39Regr::test_issue39_regression"
            ];
          });
          # Same flaky test_crafted_xml_performance as the python313 django above,
          # but Home Assistant is on python 3.14 here so that override never hits
          # this django. In django 5.2.15 the test moved to test_deserialization.py.
          # Remove once nixpkgs skips this test upstream.
          django = pyprev.django.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace tests/serializers/test_deserialization.py \
                --replace-fail "test_crafted_xml_performance" "dont_test_crafted_xml_performance"
            '';
          });
        };
      };
    })
  ];
}
