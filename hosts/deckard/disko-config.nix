{ disks ? [ "/dev/sda" ], ... }: {
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = builtins.elemAt disks 0;
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            root = {
              size = "140G";
              content = {
                type = "btrfs";
                extraArgs = [
                  "-f"
                  "-L NixOS" # Filesystem label
                ];

                # Create the initial blank snapshot
                postCreateHook = ''
                  mount -o subvol=/ /dev/disk/by-partlabel/disk-sda-root /mnt
                  btrfs sub snap -r /mnt/@ /mnt/@-blank
                  umount /mnt
                '';

                subvolumes =
                  let
                    commonOptions = [
                      "compress=zstd"
                      "noatime"
                      "nodiscard" # Prefer periodic TRIM
                    ];
                  in
                  {
                    # Root subvolume
                    "/@" = {
                      mountpoint = "/";
                      mountOptions = commonOptions;
                    };

                    # Persistent data
                    "/@persist" = {
                      mountpoint = "/persist";
                      mountOptions = commonOptions ++ [
                        "nodev"
                        "nosuid"
                        "noexec"
                      ];
                    };

                    # User home directories
                    "/@home" = {
                      mountpoint = "/home";
                      mountOptions = commonOptions ++ [
                        "nodev"
                        "nosuid"
                      ];
                    };

                    # Nix data, including the store
                    "/@nix" = {
                      mountpoint = "/nix";
                      mountOptions = commonOptions ++ [
                        "nodev"
                        "nosuid"
                      ];
                    };

                    # System logs
                    "/@log" = {
                      mountpoint = "/var/log";
                      mountOptions = commonOptions ++ [
                        "nodev"
                        "nosuid"
                        "noexec"
                      ];
                    };
                  };

              };
              priority = 3;
            };
          };
        };
      };
    };
  };
}

