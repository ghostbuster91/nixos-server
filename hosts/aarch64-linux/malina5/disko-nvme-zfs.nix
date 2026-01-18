{ lib, ... }:

let
  firmwarePartition = lib.recursiveUpdate {
    # label = "FIRMWARE";
    priority = 1;

    type = "0700"; # Microsoft basic data
    attributes = [
      0 # Required Partition
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      # mountpoint = "/boot/firmware";
      mountOptions = [
        "noatime"
      ];
    };
  };

  espPartition = lib.recursiveUpdate {
    # label = "ESP";

    type = "EF00"; # EFI System Partition (ESP)
    attributes = [
      2 # Legacy BIOS Bootable, for U-Boot to find extlinux config
    ];

    size = "1024M";
    content = {
      type = "filesystem";
      format = "vfat";
      # mountpoint = "/boot";
      mountOptions = [
        "noatime"
        "umask=0077"
      ];
    };
  };

in
{

  disko.devices = {
    disk.nvme0 = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-eui.002538d241a024cb";
      content = {
        type = "gpt";
        partitions = {

          FIRMWARE = firmwarePartition {
            label = "FIRMWARE";
            content.mountpoint = "/boot/firmware";
          };

          ESP = espPartition {
            label = "ESP";
            content.mountpoint = "/boot";
          };

          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "rpool1"; # zroot
            };
          };

        };
      };
    }; #nvme0

    zpool = {
      rpool1 =
        let
          unmountable = { type = "zfs_fs"; options = { mountpoint = "none"; }; };
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

          # zpool properties
          options = {
            ashift = "12";
            autotrim = "on"; # see also services.zfs.trim.enable
          };

          # zfs properties
          rootFsOptions = {
            # "com.sun:auto-snapshot" = "false";
            # https://jrs-s.net/2018/08/17/zfs-tuning-cheat-sheet/
            compression = "lz4";
            atime = "off";
            xattr = "sa";
            acltype = "posixacl";
            # https://rubenerd.com/forgetting-to-set-utf-normalisation-on-a-zfs-pool/
            normalization = "formD";
            dnodesize = "auto";
            mountpoint = "none";
            canmount = "off";
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
