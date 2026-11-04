_: {
  topology.self = {
    hardware.info = "Intel i7-9700K · 64 GiB RAM · GTX 1060 3GB · 2× NVMe (250 GB + 500 GB)";

    # eno1 is the only physical link (DHCP from the FunBox, so no address is
    # declared in nix — the extractor renders it as "DHCP"). The `home` network
    # is propagated over the cable declared in the repo-root topology.nix.
    # podman0/podman1/podman2 are left out deliberately: they are per-container
    # bridges for healthlog/ha-mcp, not part of the network layout.
    interfaces.eno1.type = "ethernet";
  };
}
