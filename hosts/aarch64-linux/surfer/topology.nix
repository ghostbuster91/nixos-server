{ config, lib, ... }:
let
  inherit (lib) attrNames attrValues concatMap mkMerge;

  # Every hostapd BSS sets `bridge = "br-lan"` (hostapd.nix), so each one is
  # L2-bridged into the same LAN as wan/lan0-3. The systemd-network extractor
  # only sees bridge membership that networkd declares, so the WiFi side has to
  # be derived from the hostapd config here. Deriving it instead of listing it
  # keeps the diagram correct when a BSS is added, renamed or dropped.
  #
  # The SSIDs deliberately aren't repeated as interface labels — the renderer
  # stacks those at fixed spacing and they collide. They live on the `hostapd`
  # service card instead (see hostapd.nix).
  bssInterfaces = concatMap (radio: attrNames radio.networks) (
    attrValues config.services.hostapd.radios
  );
in
{
  topology.self = {
    hardware.info = "Banana Pi BPI-R3 — MediaTek MT7986 · 2 GiB RAM · 4× LAN + WAN · WiFi 6";

    interfaces = mkMerge (
      [
        # surfer routes nothing: wan, lan0-3 and every BSS sit in br-lan, which
        # takes a DHCP lease from the FunBox. Network sharing is directional, so
        # br-lan has to share *towards* the BSSes for the LAN to propagate onto
        # the WiFi interfaces (the wan/lan0-3 side comes from the extractor).
        { br-lan.sharesNetworkWith = map (bss: (iface: iface == bss)) bssInterfaces; }
      ]
      ++ map
        (bss: {
          ${bss} = {
            type = "wifi";
            sharesNetworkWith = [ (iface: iface == "br-lan") ];
          };
        })
        bssInterfaces
    );
  };
}
