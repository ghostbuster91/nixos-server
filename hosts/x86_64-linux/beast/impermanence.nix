{ ... }:
{
  # State that should be kept across reboots, but is otherwise
  # NOT important information in any way that needs to be backed up.
  environment.persistence."/state" = {
    directories =
      [
        "/etc/NetworkManager/system-connections"
      ];
  };

  # Second NVMe drive (dpool, see disko-config.nix) wired into impermanence as
  # extra tanks. neededForBoot is required: the impermanence module asserts that
  # every persistence root is mounted in stage-1, since the bind-mounts onto the
  # rolled-back root happen early.
  fileSystems."/data/local".neededForBoot = true;
  fileSystems."/data/persist".neededForBoot = true;

  # Large, reproducibly re-downloadable data (model caches, etc.). Not backed up.
  environment.persistence."/data/local" = {
    hideMounts = true;
  };

  # Data to keep forever; dpool/safe/* is the backup boundary.
  environment.persistence."/data/persist" = {
    hideMounts = true;
  };
}
