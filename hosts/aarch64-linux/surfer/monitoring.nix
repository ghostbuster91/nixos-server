{ pkgs, ... }:
let
  # node_exporter's textfile collector reads *.prom from this dir; the
  # wifi-metrics oneshot below writes into it on a timer.
  textfileDir = "/run/node-exporter-textfile";

  # Per-station + per-channel Wi-Fi metrics. node_exporter's `wifi` collector is
  # too thin for an AP (no per-client signal/rate, no airtime), so we scrape `iw`
  # ourselves. `iw station dump` gives clean per-client fields; `iw survey dump`
  # gives channel airtime + noise for the in-use channel. Output is a textfile
  # the node_exporter textfile collector merges into /metrics.
  wifiMetrics = pkgs.writeShellScript "surfer-wifi-metrics" ''
    set -euo pipefail

    dir="${textfileDir}"
    out="$dir/wifi.prom"
    tmp="$(mktemp "$dir/wifi.prom.XXXXXX")"
    body="$(mktemp "$dir/wifi.body.XXXXXX")"

    for iface in $(iw dev | awk '/Interface/{print $2}'); do
      info="$(iw dev "$iface" info 2>/dev/null || true)"
      echo "$info" | grep -q "type AP" || continue
      ssid="$(echo "$info" | awk '/ssid/{print $2; exit}')"
      [ -n "$ssid" ] || ssid="unknown"

      { iw dev "$iface" survey dump 2>/dev/null || true; } | awk -v iface="$iface" '
        /frequency:/ { inuse = ($0 ~ /\[in use\]/) ? 1 : 0 }
        inuse && /noise:/                 { print "surfer_wifi_channel_noise_dbm{iface=\"" iface "\"} " $2 }
        inuse && /channel active time:/   { print "surfer_wifi_channel_active_ms{iface=\"" iface "\"} " $(NF-1) }
        inuse && /channel busy time:/     { print "surfer_wifi_channel_busy_ms{iface=\"" iface "\"} " $(NF-1) }
        inuse && /channel receive time:/  { print "surfer_wifi_channel_receive_ms{iface=\"" iface "\"} " $(NF-1) }
        inuse && /channel transmit time:/ { print "surfer_wifi_channel_transmit_ms{iface=\"" iface "\"} " $(NF-1) }
      ' >> "$body"

      { iw dev "$iface" station dump 2>/dev/null || true; } | awk -v iface="$iface" -v ssid="$ssid" '
        function lbl() { return "{iface=\"" iface "\",ssid=\"" ssid "\",mac=\"" mac "\"} " }
        /^Station/               { mac=$2; n++ }
        /^[ \t]*signal:/         { print "surfer_wifi_station_signal_dbm" lbl() $2 }
        /^[ \t]*tx bitrate:/     { print "surfer_wifi_station_tx_bitrate_mbps" lbl() $3 }
        /^[ \t]*rx bitrate:/     { print "surfer_wifi_station_rx_bitrate_mbps" lbl() $3 }
        /^[ \t]*rx bytes:/       { print "surfer_wifi_station_rx_bytes" lbl() $3 }
        /^[ \t]*tx bytes:/       { print "surfer_wifi_station_tx_bytes" lbl() $3 }
        /^[ \t]*connected time:/ { print "surfer_wifi_station_connected_seconds" lbl() $3 }
        /^[ \t]*inactive time:/  { print "surfer_wifi_station_inactive_ms" lbl() $3 }
        END                      { print "surfer_wifi_stations{iface=\"" iface "\",ssid=\"" ssid "\"} " (n+0) }
      ' >> "$body"
    done

    # Emit valid Prometheus text: sort so each metric family is contiguous, then
    # inject that family's HELP/TYPE immediately before its first sample (the text
    # parser requires HELP/TYPE to directly precede the family's samples).
    sort "$body" | awk '
      BEGIN {
        ty["surfer_wifi_stations"]="gauge";                  he["surfer_wifi_stations"]="Associated stations per BSS."
        ty["surfer_wifi_station_signal_dbm"]="gauge";        he["surfer_wifi_station_signal_dbm"]="Per-station signal (dBm)."
        ty["surfer_wifi_station_tx_bitrate_mbps"]="gauge";   he["surfer_wifi_station_tx_bitrate_mbps"]="Per-station TX PHY rate (Mbit/s)."
        ty["surfer_wifi_station_rx_bitrate_mbps"]="gauge";   he["surfer_wifi_station_rx_bitrate_mbps"]="Per-station RX PHY rate (Mbit/s)."
        ty["surfer_wifi_station_rx_bytes"]="gauge";          he["surfer_wifi_station_rx_bytes"]="Per-station RX bytes this session."
        ty["surfer_wifi_station_tx_bytes"]="gauge";          he["surfer_wifi_station_tx_bytes"]="Per-station TX bytes this session."
        ty["surfer_wifi_station_connected_seconds"]="gauge"; he["surfer_wifi_station_connected_seconds"]="Per-station association age (s)."
        ty["surfer_wifi_station_inactive_ms"]="gauge";       he["surfer_wifi_station_inactive_ms"]="Per-station inactivity (ms)."
        ty["surfer_wifi_channel_noise_dbm"]="gauge";         he["surfer_wifi_channel_noise_dbm"]="Noise floor of the in-use channel (dBm)."
        ty["surfer_wifi_channel_active_ms"]="counter";       he["surfer_wifi_channel_active_ms"]="Channel active time since interface up (ms)."
        ty["surfer_wifi_channel_busy_ms"]="counter";         he["surfer_wifi_channel_busy_ms"]="Channel busy time since interface up (ms)."
        ty["surfer_wifi_channel_receive_ms"]="counter";      he["surfer_wifi_channel_receive_ms"]="Channel receive time since interface up (ms)."
        ty["surfer_wifi_channel_transmit_ms"]="counter";     he["surfer_wifi_channel_transmit_ms"]="Channel transmit time since interface up (ms)."
      }
      {
        name = $1; sub(/[{ ].*/, "", name)
        if (name != prev) {
          if (name in he) print "# HELP " name " " he[name]
          if (name in ty) print "# TYPE " name " " ty[name]
          prev = name
        }
        print
      }
    ' > "$tmp"

    rm -f "$body"
    chmod 0644 "$tmp"
    mv "$tmp" "$out"
  '';
in
{
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
          "textfile"
        ];
        extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
        port = 9002;
      };
    };
  };

  # Create the textfile dir (world-readable so node_exporter can read it) and
  # refresh the Wi-Fi metrics every 30s via a oneshot + timer.
  systemd.tmpfiles.rules = [ "d ${textfileDir} 0755 root root -" ];

  systemd.services.surfer-wifi-metrics = {
    description = "Collect per-station/channel Wi-Fi metrics for node_exporter";
    after = [ "hostapd.service" ];
    path = [ pkgs.iw pkgs.gawk pkgs.coreutils pkgs.gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${wifiMetrics}";
    };
  };

  systemd.timers.surfer-wifi-metrics = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1m";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
    };
  };

  # Journal->Loki shipping comes from the shared logs-alloy module; surfer has no
  # `meta`/homelab.ext-domain, so point it at the Loki endpoint directly.
  homelab.logs.lokiPushUrl = "https://loki.typesafebrew.dev/loki/api/v1/push"; ##TODO
}
