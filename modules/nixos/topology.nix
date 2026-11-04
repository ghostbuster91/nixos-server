{ config, lib, inputs, ... }:
let
  inherit (lib) mkIf;

  # Every deployed host has its tailnet address declared in secrets/meta.nix.age
  # as `homelab.<host>.vlan.ip`. Hosts without one (none today) simply get no
  # tailscale0 interface on the diagram instead of failing to evaluate.
  tailnetIp = config.homelab.${config.networking.hostName}.vlan.ip or null;
in
{
  # Opt a host into nix-topology. Importing this (instead of
  # `inputs.nix-topology.nixosModules.default` directly) is what puts the host
  # on the rendered diagram, and it fills in the one interface no extractor can
  # see: tailscale0, whose address is handed out by headscale at runtime.
  #
  # Host-specific topology bits (hardware info, WiFi interfaces, addresses the
  # extractors can't derive) belong in `hosts/<arch>/<host>/topology.nix`; the
  # physical cabling and non-NixOS devices live in the repo-root `topology.nix`.
  imports = [ inputs.nix-topology.nixosModules.default ];

  topology.self.interfaces.tailscale0 = mkIf (tailnetIp != null) {
    addresses = [ tailnetIp ];
    network = "tailnet";
    virtual = true;
    type = "wireguard";
    # The tailnet is a full mesh, so rendering its edges would draw a line
    # between every pair of hosts and bury the actual cabling. Hide them in the
    # main view — the network-centric diagram still shows the tailnet.
    renderer.hidePhysicalConnections = true;
  };
}
