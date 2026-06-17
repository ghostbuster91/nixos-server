{ disks ? [ "/dev/sda" ], ... }: {
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = builtins.elemAt disks 0;
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "4M";
              type = "EF02";
              priority = 1;
            };

            esp = {
              name = "ESP";
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
              priority = 2;
            };
            root = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "rpool1";
              };
              priority = 3;
            };
          };
        };
      };
      sdb = {
        type = "disk";
        device = builtins.elemAt disks 1;
        content = {
          type = "gpt";
          partitions = {
            data = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "dpool";
              };
            };
          };
        };
      };
    };
    zpool =
      let
        unmountable = { type = "zfs_fs"; };
        filesystem = mountpoint: {
          type = "zfs_fs";
          options = {
            canmount = "noauto";
            inherit mountpoint;
          };
          inherit mountpoint;
        };
      in
      {
        rpool1 = {
          type = "zpool";

          rootFsOptions = {
            compression = "lz4";
            "com.sun:auto-snapshot" = "false";
            canmount = "off";
            xattr = "sa";
            atime = "off";
          };
          options = {
            ashift = "12";
            autotrim = "on";
            compatibility = "grub2";
          };
          datasets = {
            "local" = unmountable;
            "local/root" = filesystem "/" // {
              postCreateHook = "zfs snapshot rpool1/local/root@blank";
            };
            "local/nix" = filesystem "/nix";
            "local/state" = filesystem "/state";

            "safe" = unmountable;
            "safe/persist" = filesystem "/persist";
          };
        };
        dpool = {
          type = "zpool";
          rootFsOptions = {
            compression = "lz4";
            "com.sun:auto-snapshot" = "false";
            canmount = "off";
            xattr = "sa";
            atime = "off";
          };
          options = {
            ashift = "12";
            autotrim = "on";
          };
          datasets = {
            # Not backed up.
            "local" = filesystem "/data/local";

            # Backup boundary, mirrors rpool1/safe/* — snapshot dpool/safe to
            # capture everything that should be preserved.
            "safe" = unmountable;
            "safe/persist" = filesystem "/data/persist";
          };
        };
      };
  };
}

