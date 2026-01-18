{ ... }:
{
  # Give agenix access to the hostkey independent of impermanence activation
  # age.identityPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # State that should be kept across reboots, but is otherwise
  # NOT important information in any way that needs to be backed up.
  environment.persistence."/state" = {
    hideMounts = true;
    directories =
      [
        "/var/lib/iwd"
        "/etc/NetworkManager/system-connections"
      ];
  };
}
