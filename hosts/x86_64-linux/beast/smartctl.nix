{ ... }:
{
  # SMART health for beast's two NVMe SSDs (nvme0 = rpool1, nvme1 = dpool).
  #
  # smartctl_exporter (not the node_exporter `smartmon.sh` textfile collector)
  # because the textfile script routes NVMe devices through its SCSI attribute
  # parser, which matches key names NVMe's smartctl output never emits — you get
  # device_info and nothing else. This exporter reads the NVMe SMART/Health log
  # directly, so `percentage_used` / `available_spare` / `media_errors` — the
  # metrics that actually predict an SSD failure — are populated.
  #
  # Bound to loopback with no firewall opening: prometheus and grafana both run
  # on beast (see modules/nixos/prometheus/server.nix), so nothing off-host ever
  # needs to reach port 9633.
  #
  # The nixpkgs module handles the privileges: the binary has smartmontools'
  # path patched in, the unit gets CAP_SYS_RAWIO, and a udev rule grants the
  # `smartctl-exporter-access` group rw on /dev/nvme[0-9]*.
  services.prometheus.exporters.smartctl = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9633;
    openFirewall = false;
  };
}
