{ config, lib, ... }:
let
  inherit (config.lib.topology) mkConnection;
  inherit (lib) concatStringsSep filter hasPrefix map mkForce;

  addressesOf = family: map (a: a.address) config.networking.interfaces.eth0.${family}.addresses;
in
{
  topology.self = {
    hardware.info = "Hetzner vServer — 3 vCPU · 4 GiB RAM · 76 GB";

    interfaces.eth0 = {
      # eth0's addresses come from `networking.interfaces.eth0` (networking.nix,
      # fed from homelab.vps.interfaces). The extractor takes *every* address,
      # link-local v6 included, and the renderer collapses the list onto one
      # line — so drop fe80:: and separate the two routable ones explicitly.
      addresses = mkForce (
        addressesOf "ipv4" ++ filter (a: !hasPrefix "fe80:" a) (addressesOf "ipv6")
      );
      addressFormatter = concatStringsSep "  ·  ";
      gateways = [ config.networking.defaultGateway.address ];

      # The uplink itself is declared on the `internet` node in the repo-root
      # topology.nix — thunder has no LAN side at all.
    };

    # Peer edges are hidden in the main view (see modules/nixos/topology.nix),
    # but the mesh is anchored here so the network-centric diagram draws the
    # tailnet around its control server instead of as disconnected stubs.
    interfaces.tailscale0.physicalConnections = map (host: mkConnection host "tailscale0") [
      "beast"
      "malina5"
      "surfer"
    ];
  };

  # thunder runs the headscale control server, so it owns the tailnet
  # definition; every other host just joins it via the shared
  # modules/nixos/topology.nix. The dashed style marks it as virtual.
  topology.networks.tailnet = {
    name = "Tailnet (headscale)";
    cidrv4 = config.homelab.vpnCidr;
    style = {
      primaryColor = "#9378de";
      secondaryColor = null;
      pattern = "dashed";
    };
  };
}
