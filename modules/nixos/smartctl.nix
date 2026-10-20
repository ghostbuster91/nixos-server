{ config, pkgs, ... }:
{
  # SMART/NVMe health exporter. Imported by every host with an NVMe worth
  # watching: beast (nvme0 = rpool1, nvme1 = dpool) and malina5 (nvme0 = rpool1,
  # the Pi 5's PCIe drive).
  #
  # smartctl_exporter rather than the node_exporter `smartmon.sh` textfile
  # collector: that script routes NVMe devices through its SCSI attribute
  # parser, which matches key names NVMe's smartctl output never emits, so you
  # get device_info and nothing else. This exporter reads the NVMe SMART/Health
  # log directly, so `percentage_used` / `available_spare` / `media_errors` --
  # the metrics that actually predict an SSD failure -- are populated.
  #
  # The nixpkgs module handles the privileges: smartmontools' path is patched
  # into the binary, the unit gets CAP_SYS_RAWIO, and a udev rule grants the
  # `smartctl-exporter-access` group rw on /dev/nvme[0-9]*.
  services.prometheus.exporters.smartctl = {
    enable = true;
    port = 9633;

    # Scraped over the tailnet as `<host>.tail.<domain>:9633`, same as every
    # other exporter in the fleet -- including on beast, which hosts prometheus
    # and therefore reaches its own address via `lo`.
    #
    # `openFirewall` is deliberately off: it renders an *unscoped*
    # `ip46tables -A nixos-fw -p tcp --dport 9633` (via extraCommands, not
    # allowedTCPPorts), which would accept on every interface including the LAN.
    # The interface-scoped rule below is what we want.
    openFirewall = false;
  };

  networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
    config.services.prometheus.exporters.smartctl.port
  ];

  # The module's udev rule is `ACTION=="add"`, so it only grants the ACL when a
  # device appears -- at boot or on hotplug. On a live `nixos-rebuild switch` /
  # `deploy` the rule lands but is never replayed against the NVMe devices that
  # were already present, so /dev/nvme* stay root:root 0600 and the exporter
  # cannot open them. It fails *silently*: `smartctl --scan` still counts the
  # drives, so the exporter happily serves `smartctl_devices N` and not one
  # per-device series, and every dashboard panel reads "No data".
  #
  # Replaying the add events before the exporter starts fixes that for the first
  # activation and keeps it true if a drive is ever hot-added. `+` runs this as
  # root (the unit itself is an unprivileged user) and `--settle` waits for the
  # ACL to actually be applied rather than racing it.
  systemd.services.prometheus-smartctl-exporter.serviceConfig.ExecStartPre = [
    "+${pkgs.systemd}/bin/udevadm trigger --action=add --subsystem-match=nvme --settle"
  ];
}
