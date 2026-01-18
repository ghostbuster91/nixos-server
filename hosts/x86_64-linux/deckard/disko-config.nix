{ disks ? [ "/dev/sda" ], ... }: {
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        device = builtins.elemAt disks 0;
        content = {
          type = "gpt";
          partitions = {
            grub = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            boot = {
              size = "512M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
              priority = 2;
              hybrid.mbrBootableFlag = true;
            };
            root = {
              size = "128G";
              content = {
                type = "zfs";
                pool = "rpool1";
              };
              priority = 4;
            };
          };
        };
      };
    };
    zpool = {
      rpool1 =
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
    };
  };
}

