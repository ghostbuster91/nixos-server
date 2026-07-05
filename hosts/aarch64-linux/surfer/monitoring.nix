{ ... }: {
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        # TODO test perf impact of these modules
        enabledCollectors = [
          "arp"
          "hwmon"
          "cpu"
          "diskstats"
          "ethtool"
          "interrupts"
          "ksmd"
          "lnstat"
          "mountstats"
          "processes"
          "systemd"
          "wifi"
          "tcpstat"
          "netdev"
          "netstat"
          "network_route"
          "netclass"
          "sockstat"
          "stat"
          "conntrack"
        ];
        port = 9002;
      };
    };
  };
  # Journal->Loki shipping comes from the shared logs-alloy module; surfer has no
  # `meta`/homelab.ext-domain, so point it at the Loki endpoint directly.
  homelab.logs.lokiPushUrl = "https://loki.typesafebrew.dev/loki/api/v1/push"; ##TODO
}
