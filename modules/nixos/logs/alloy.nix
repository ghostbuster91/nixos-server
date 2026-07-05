{ config, lib, ... }:
let
  cfg = config.homelab.logs;
in
{
  # Ships the systemd journal to Loki. Replaces promtail, which was removed in
  # nixpkgs 26.05 (EOL). Equivalent to the old promtail journal scrape:
  # 12h max age, job=systemd-journal + host labels, and __journal__systemd_unit
  # relabeled to `unit`.
  options.homelab.logs.lokiPushUrl = lib.mkOption {
    type = lib.types.str;
    # Hosts that import the `meta` module derive this from their ext-domain;
    # hosts without it (e.g. surfer) can override the URL directly.
    default = "https://loki.${config.homelab.ext-domain}/loki/api/v1/push";
    description = "Loki push endpoint that Alloy forwards the journal to.";
  };

  config = {
    services.alloy = {
      enable = true;
      # promtail ran with its own HTTP server disabled; keep Alloy's UI/metrics
      # server on loopback and skip anonymous usage reporting.
      extraFlags = [
        "--server.http.listen-addr=127.0.0.1:12345"
        "--disable-reporting"
      ];
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.relabel "journal" {
        forward_to = []

        rule {
          source_labels = ["__journal__systemd_unit"]
          target_label  = "unit"
        }
      }

      loki.source.journal "journal" {
        max_age       = "12h"
        relabel_rules = loki.relabel.journal.rules
        forward_to    = [loki.write.default.receiver]
        labels        = {
          job  = "systemd-journal",
          host = "${config.networking.hostName}",
        }
      }

      loki.write "default" {
        endpoint {
          url = "${cfg.lokiPushUrl}"
        }
      }
    '';
  };
}
