{ config, ... }:
let
  inherit (config.lib.topology)
    mkInternet
    mkRouter
    mkDevice
    mkConnection
    ;

  # Addresses of the home network are secrets (secrets/meta.nix.age via
  # modules/nixos/meta.nix), so they can't be literals here. The global
  # topology module is handed every `nixosConfigurations` by nix-topology's
  # flake module, so read them back off a host that imports `meta` — surfer is
  # the one wired into the FunBox and the one that polls it for metrics.
  lan = config.nixosConfigurations.surfer.config.homelab.lan;
in
{
  # Global topology: the facts no single NixOS config can know — the physical
  # cabling and the non-NixOS devices on the LAN. Everything else is either
  # extracted from the host configs (interfaces via the systemd-network /
  # networking.interfaces extractors, services via the service extractor) or
  # declared in `hosts/<arch>/<host>/topology.nix`.
  #
  # Render with: nix build .#topology.x86_64-linux.config.output

  nodes.internet = mkInternet {
    connections = [
      (mkConnection "funbox" "wan")
      # thunder is a Hetzner VPS: it hangs directly off the internet, not off
      # the home LAN. It reaches the other hosts only over the tailnet.
      (mkConnection "thunder" "eth0")
    ];
  };

  # Orange's ISP gateway, and the only actual router here. surfer bridges its
  # `wan` port into br-lan (hosts/aarch64-linux/surfer/network.nix), so it is a
  # dumb switch + WiFi AP behind the FunBox rather than a router of its own —
  # DHCP, NAT and the default route all live on the FunBox.
  #
  # Port numbering is nominal: the FunBox is not managed from here, so the
  # lanN ids only record *that* these four things are plugged into it.
  nodes.funbox = mkRouter "FunBox" {
    info = "Orange FunBox — ISP gateway at ${lan.gateway.ip}, DHCP + NAT";
    interfaceGroups = [
      [ "lan1" "lan2" "lan3" "lan4" ]
      [ "wan" ]
    ];
    interfaces.lan1.network = "home";
    connections = {
      lan1 = mkConnection "surfer" "wan";
      lan2 = mkConnection "beast" "eno1";
      lan3 = mkConnection "malina5" "end0";
      lan4 = mkConnection "slzb-06" "eth0";
    };
  };

  # Networked Zigbee coordinator. zigbee2mqtt on malina5 talks to it over TCP
  # rather than a local serial port — see `serial.port` in
  # modules/nixos/zigbee2mqtt.nix, which reads the same secret.
  nodes.slzb-06 = mkDevice "SLZB-06" {
    info = "SMLIGHT SLZB-06 — Zigbee coordinator (TCP 6638)";
    interfaceGroups = [ [ "eth0" ] ];
    interfaces.eth0.addresses = [ lan.devices.slzb06.ip ];
  };

  networks.home = {
    name = "Home LAN";
    cidrv4 = lan.cidrv4;
  };
}
