{ lib, ... }: {

  # filesystem modifications needed for impermanence
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/var/log".neededForBoot = true;

  # reset / at each boot
  # Note `lib.mkBefore` is used instead of `lib.mkAfter` here.

  boot.initrd.postDeviceCommands = lib.mkAfter ''
    mkdir /btrfs_tmp
    mount /dev/disk/by-partlabel/disk-sda-root /btrfs_tmp
    if [[ -e /btrfs_tmp/root ]]; then
        mkdir -p /btrfs_tmp/old_roots
        timestamp=$(date --date="@$(stat -c %Y /btrfs_tmp/root)" "+%Y-%m-%-d_%H:%M:%S")
        mv /btrfs_tmp/root "/btrfs_tmp/old_roots/$timestamp"
    fi

    delete_subvolume_recursively() {
        IFS=$'\n'
        for i in $(btrfs subvolume list -o "$1" | cut -f 9- -d ' '); do
            delete_subvolume_recursively "/btrfs_tmp/$i"
        done
        btrfs subvolume delete "$1"
    }

    for i in $(find /btrfs_tmp/old_roots/ -maxdepth 1 -mtime +30); do
        delete_subvolume_recursively "$i"
    done

    btrfs subvolume create /btrfs_tmp/root
    umount /btrfs_tmp
  '';

  # boot = {
  #   initrd = {
  #     # systemd unit from https://discourse.nixos.org/t/impermanence-vs-systemd-initrd-w-tpm-unlocking/25167/3
  #     systemd = {
  #       enable = true;
  #       services.rollback = {
  #         description = "Rollback Btrfs root subvolume to a pristine state";
  #         wantedBy = [ "initrd.target" ];
  #         after = [ "systemd-cryptsetup@root.service" ];
  #         before = [ "sysroot.mount" ];
  #         unitConfig.DefaultDependencies = "no";
  #         serviceConfig.Type = "oneshot";
  #         # Script from https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html#darling-erasure and https://github.com/talyz/nixos-config/blob/b95e5170/machines/evals/configuration.nix#L67-76 plus my own changes (namely snapshotting the old root read-only)
  #         script = ''
  #           mkdir /btrfs_tmp
  #           mount -o subvol=/ /dev/disk/by-partlabel/disk-sda-root /btrfs_tmp
  #
  #           if [[ -e /btrfs_tmp/@ ]]; then
  #             btrfs sub li -o /btrfs_tmp/@ |
  #             cut -f9 -d' ' |
  #             while read subvol; do
  #               echo "Deleting $subvol subvolume..." &&
  #               btrfs sub del "/btrfs_tmp/$subvol"
  #             done
  #
  #             echo "Snapshotting @ subvolume..." &&
  #             btrfs sub snap -r /btrfs_tmp/@ /btrfs_tmp/@-"$(date +%FT%T)"
  #
  #             echo "Deleting old @ subvolume..." &&
  #             btrfs sub del /btrfs_tmp/@
  #           fi
  #
  #           echo "Restoring blank @ subvolume..." &&
  #           btrfs sub snap /btrfs_tmp/@-blank /btrfs_tmp/@
  #           sync
  #           umount /btrfs_tmp
  #         '';
  #       };
  #     };
  #   };
  #
  #   tmp.cleanOnBoot = true;
  # };

}
