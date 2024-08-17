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
              size = "160G";
              content = {
                type = "zfs";
                pool = "rpool1";
              };
              priority = 2;
            };
            swap = {
              size = "100%";
              content = {
                type = "swap";
                randomEncryption = false;
              };
              priority = 3;
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
              mountpoint = "legacy";
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

