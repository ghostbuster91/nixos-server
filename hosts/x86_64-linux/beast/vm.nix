{ pkgs, username, ... }:
{
  environment.systemPackages = [ pkgs.qemu_kvm ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      ovmf.enable = true;
      swtpm.enable = true;
    };
  };

  users.users.${username}.extraGroups = [ "libvirtd" "kvm" ];

  environment.persistence."/local".directories = [
    "/var/lib/libvirt"
  ];
}
