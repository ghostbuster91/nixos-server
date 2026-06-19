{ pkgs, username, ... }:
{
  environment.systemPackages = [ pkgs.qemu_kvm pkgs.virt-manager pkgs.passt ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  users.users.${username}.extraGroups = [ "libvirtd" "kvm" ];

  environment.persistence."/local".directories = [
    "/var/lib/libvirt"
  ];
}
