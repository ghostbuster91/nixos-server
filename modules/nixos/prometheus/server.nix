{ config, pkgs, lib, ... }:
let
  roleName = "prometheus";
  cfg = config.services.prometheus;
  # Loopback-only: alertmanager and the bridge are both on this host. Port 8000
  # is the upstream default and is free here (the local web apps sit on 808x).
  ntfyBridgeAddr = "127.0.0.1:8000";
in
{
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/${config.services.prometheus.stateDir}";
      user = "prometheus";
      group = "prometheus";
      mode = "0700";
    }
  ];

  environment.persistence."/state".directories = [
    {
      # alertmanager runs with DynamicUser=true, so there is no static
      # alertmanager user/group for impermanence to chown the bind-mount
      # source to. Leave ownership to systemd, which chowns the state dir
      # to the dynamic UID at service start (same pattern as esphome/whisper).
      directory = "/var/lib/private/alertmanager";
      mode = "0700";
    }
  ];
  age.secrets."prometheus-hass-token" = {
    file = ../../../secrets/prometheus-hass-token.age;
    mode = "440";
    owner = "prometheus";
    group = "prometheus";
  };
  # There is deliberately no secret for alertmanager: ntfy needs no credentials
  # (the bridge below talks to it over the tailnet, where it is open by design),
  # and nothing else in alertmanager.yml is sensitive. The old
  # `secrets/alertmanager.age` held only the pushover user key and API token,
  # substituted in via `environmentFile`; it went away with the pushover
  # receiver (`git log -- secrets/alertmanager.age` if it is ever needed back).
  systemd.services.nginx = {
    requires = [ "prometheus.service" ];
  };
  services = {
    prometheus = {
      enable = true;
      port = 9001;
      listenAddress = "127.0.0.1";

      # Without this, the `generatorURL` prometheus stamps on every alert points
      # at its own listen address (http://beast:9001) -- loopback-bound, so the
      # link is dead everywhere except on beast itself. Point it at the public
      # vhost instead so the notification's click-through actually opens the
      # alert's query (see the X-Click header on the ntfy bridge below).
      webExternalUrl = "https://${roleName}.${config.homelab.ext-domain}";

      # By default the check verifies also if all referenced paths exist.
      # This however cannot work if any of these paths refers to age/sops secrets as these files are created during the activation phase.
      checkConfig = "syntax-only";

      # Test alertmanager (include `severity` -- the ntfy bridge's priority and
      # tag expressions are keyed off it, and an alert without it is forwarded
      # at ntfy's default priority with a warning in the bridge's log):
      # curl -H 'Content-Type: application/json' -d '[{"labels":{"alertname":"myalert","severity":"critical"}}]' http://127.0.0.1:9093/api/v2/alerts
      alertmanagers = [
        {
          scheme = "http";
          path_prefix = "/";
          static_configs = [{ targets = [ "127.0.0.1:${toString config.services.prometheus.alertmanager.port}" ]; }];
        }
      ];

      # alertmanager might fail to start if impermanence mounts esphome directory first. In this case disable temporary esphome mount and restart alertmanager
      alertmanager = {
        enable = true;
        logLevel = "debug";

        extraFlags = [
          "--cluster.listen-address=" # disables HA mode
        ];
        configuration = {
          # ntfy is the only channel; there is nothing to route between, so one
          # receiver and one route is the whole config.
          receivers = [
            {
              # alertmanager's generic webhook posts its own JSON, which ntfy
              # would publish verbatim as the message body -- hence the
              # alertmanager-ntfy bridge below, which turns each alert into a
              # titled ntfy push with a priority derived from `severity`.
              name = "ntfy";
              webhook_configs = [
                {
                  send_resolved = true;
                  url = "http://${ntfyBridgeAddr}/hook";
                }
              ];
            }
          ];

          # Mute the 80% warning while the 90% critical is firing for the same
          # pool, so a filling disk is one notification, not two.
          inhibit_rules = [
            {
              source_matchers = [ ''severity="critical"'' ];
              target_matchers = [ ''severity="warning"'' ];
              equal = [ "host" "pool" ];
            }
          ];

          route = {
            receiver = "ntfy";
            group_wait = "30s";
            group_interval = "2m";
            repeat_interval = "4h";
            # `host` and `pool` are the labels that distinguish one disk from
            # another, so group on them: beast/rpool1 filling up is a different
            # notification from malina5/rpool1 filling up. (The previous
            # grouping included `alias`, which nothing in this fleet emits.)
            group_by = [ "alertname" "host" "pool" ];
          };
        };
      };

      # Forwards alertmanager webhooks to ntfy on malina5 
      alertmanager-ntfy = {
        enable = true;
        settings = {
          http.addr = ntfyBridgeAddr;
          ntfy = {
            baseurl = "https://ntfy.${config.homelab.ext-domain}";
            notification = {
              topic = "homelab";
              # The two tiers the alert rules set up, mapped onto ntfy
              # priorities: a `warning` arrives as an ordinary notification,
              # a `critical` as `urgent`, which pops up and overrides the
              # phone's do-not-disturb. This is the knob to turn if the 90%
              # alert should be less (or more) insistent. gval expression, with
              # the alert's fields at the top level.
              #
              # gval errors on a missing map key rather than yielding nothing,
              # so an alert without a `severity` label is forwarded at ntfy's
              # default priority and logs a warning here. Every rule gets one
              # from the mapper in alert-rules.nix, so in practice only a
              # hand-posted alert can hit that.
              priority = ''status == "resolved" ? "default" : (labels["severity"] == "critical" ? "urgent" : "default")'';
              tags = [
                { tag = "white_check_mark"; condition = ''status == "resolved"''; }
                { tag = "rotating_light"; condition = ''status == "firing" && labels["severity"] == "critical"''; }
                { tag = "warning"; condition = ''status == "firing" && labels["severity"] == "warning"''; }
              ];
              # Titles/descriptions come from the rules' `summary`/`description`
              # annotations (alert-rules.nix) via the module's default
              # templates; only the click-through needs adding -- tapping the
              # push opens the alert's query in prometheus' UI.
              #
              # The bridge also appends every alert label as a text tag
              # (`host = beast`, `pool = rpool1`, ...) with no way to turn that
              # off, so the push already shows which host and pool it is about.
              templates.headers."X-Click" = "{{ .GeneratorURL }}";
            };
          };
        };
      };

      ruleFiles = [
        (pkgs.writeText "prometheus-rules.yml" (
          builtins.toJSON {
            groups = [
              {
                name = "alerting-rules";
                rules = import ./alert-rules.nix { inherit lib; };
              }
            ];
          }
        ))
      ];


      scrapeConfigs =
        let
          scrape_interval = "60s";
          exporters = config.services.prometheus.exporters;

          # Every exporter in the fleet is reached the same way: over the
          # tailnet as `<host>.tail.<domain>:<port>`. That holds for beast too,
          # even though it hosts prometheus — it resolves its own name to a
          # local address, so the packet arrives on `lo`, which nixos-fw accepts
          # unconditionally. Exporter ports are opened on tailscale0 only, never
          # via the exporter modules' `openFirewall` (that rule is unscoped).
          #
          # One static_config per host, each carrying a short `host` label.
          # Dashboards and alert rules key off `host` rather than `instance`, so
          # they read "beast nvme0" instead of repeating the full
          # `beast.tail.<domain>:9633`; `instance` is still there when wanted.
          # No currently-scraped exporter exposes a `host` label of its own, so
          # nothing gets renamed to `exported_host` by this.
          tailTargets = port: hosts: map
            (host: {
              targets = [ "${host}.tail.${config.homelab.ext-domain}:${toString port}" ];
              labels = { inherit host; };
            })
            hosts;
        in
        [
          {
            # Keep this job first — grafana/default.nix derives the datasource's
            # timeInterval from `elemAt scrapeConfigs 0`.
            job_name = "node_exporter";
            inherit scrape_interval;
            static_configs = tailTargets exporters.node.port [ "beast" "surfer" "malina5" "thunder" ];
          }
          {
            job_name = "haas";
            metrics_path = "/api/prometheus";
            inherit scrape_interval;
            # Long-Lived Access Token
            authorization.credentials_file = config.age.secrets."prometheus-hass-token".path;
            static_configs = [{
              targets = [ "ha.${config.homelab.ext-domain}" ];
            }];
          }
          {
            # Every host importing nixosModules.zfs runs this exporter; scrape
            # all of them so pool health/capacity is actually collected. (deckard
            # imports it too but is decommissioned.)
            job_name = "zfs";
            inherit scrape_interval;
            static_configs = tailTargets exporters.zfs.port [ "beast" "malina5" ];
          }
          {
            # prometheus-client enables the systemd exporter alongside node, so
            # scrape it everywhere that module is imported -- otherwise the unit
            # runs for nothing.
            job_name = "systemd";
            inherit scrape_interval;
            static_configs = tailTargets exporters.systemd.port [ "beast" "malina5" "thunder" ];
          }
          {
            job_name = "smartctl";
            inherit scrape_interval;
            static_configs = tailTargets exporters.smartctl.port [ "beast" "malina5" ];
          }
          {
            job_name = "unbound";
            inherit scrape_interval;
            static_configs = tailTargets 9167 [ "thunder" ];
          }
        ];
    };

    nginx.virtualHosts."${roleName}.${config.homelab.ext-domain}" = {
      useACMEHost = config.homelab.ext-domain;
      forceSSL = true;

      # Prometheus has no auth of its own, so gate the UI/API behind
      # oauth2-proxy. Grafana queries this datasource over loopback
      # (see grafana/default.nix), bypassing this proxy.
      oauth2 = {
        enable = true;
        allowedGroups = [ "access_prometheus" ];
      };

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString cfg.port}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
