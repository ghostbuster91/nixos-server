{ ... }:
{
  # State that should be kept across reboots, but is otherwise
  # NOT important information in any way that needs to be backed up.
  environment.persistence."/state" = {
    directories =
      [
        "/var/lib/iwd"
        "/etc/NetworkManager/system-connections"
      ];
  };
}
