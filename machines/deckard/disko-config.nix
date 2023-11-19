{ disks, ... }: {
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = builtins.elemAt disks 0;
        content = {
          type = "table";
          format = "gpt";
          partitions = [
            {
              name = "boot";
              start = "0";
              end = "1M";
              part-type = "primary";
              flags = [ "bios_grub" ];
            }
            {
              name = "root";
              # leave space for the grub aka BIOS boot
              start = "1M";
              end = "-32G";
              part-type = "primary";
              bootable = true;
              content = {
                type = "zfs";
                pool = "rpool1";
              };
            }
            {
              name = "swap";
              start = "-32G";
              end = "100%";
              content = {
                type = "swap";
                randomEncryption = false;
              };
            }
          ];
        };
      };
    };
    zpool = {
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
        };
        datasets = {
          zroot = {
            type = "zfs_fs";
            mountpoint = "/";
            postCreateHook = "zfs snapshot rpool1/zroot@blank";
            options = {
              mountpoint = "legacy";
            };
          };
          znix = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              mountpoint = "legacy";
            };
          };
          zvar = {
            type = "zfs_fs";
            mountpoint = "/var";
            options = {
              mountpoint = "legacy";
            };
          };
        };
      };
    };
  };
}

