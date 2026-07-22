{ pkgs, username, inputs, ... }:
{
  imports = [ inputs.nixvirt.nixosModules.default ];

  environment.systemPackages = [ pkgs.qemu_kvm pkgs.virt-manager pkgs.passt ];

  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  # Declarative libvirt domains (NixVirt). The ubuntu-vpn domain definition
  # lives in ./ubuntu-vpn.xml and is (re)defined on every activation, so a ZFS
  # rollback of the (impermanent) root can no longer lose it. The backing disk
  # is on the persisted /data/local dataset (see disko-config.nix).
  virtualisation.libvirt = {
    enable = true;
    connections."qemu:///system".domains = [
      {
        definition = ./ubuntu-vpn.xml;
        active = true;
      }
    ];
  };

  users.users.${username}.extraGroups = [ "libvirtd" "kvm" ];

  environment.persistence."/local".directories = [
    "/var/lib/libvirt"
  ];
}
