{ config, pkgs, lib, ... }:
let
  roleName = "prometheus";
  cfg = config.services.prometheus;
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
  age.secrets."alertmanager" = {
    file = ../../../secrets/alertmanager.age;
    mode = "440";
    owner = "prometheus";
    group = "prometheus";
  };
  systemd.services.nginx = {
    requires = [ "prometheus.service" ];
  };
  services = {
    prometheus = {
      enable = true;
      port = 9001;
      listenAddress = "127.0.0.1";

      # By default the check verifies also if all referenced paths exist.
      # This however cannot work if any of these paths refers to age/sops secrets as these files are created during the activation phase.
      checkConfig = "syntax-only";

      # Test alertmanager
      # curl -H 'Content-Type: application/json' -d '[{"labels":{"alertname":"myalert"}}]' http://127.0.0.1:9093/api/v2/alerts
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

        # Secret content all variables content
        # example:
        # alertmanager: |
        #  var_name1=value1
        #  var_name2=value2
        environmentFile = config.age.secrets.alertmanager.path;
        extraFlags = [
          "--cluster.listen-address=" # disables HA mode
        ];
        configuration = {
          receivers = [
            {
              name = "pushover";
              pushover_configs = [
                {
                  send_resolved = true;
                  user_key = "$PUSHOVER_USER_KEY";
                  token = "$PUSHOVER_TOKEN";
                }
              ];
            }
          ];

          route = {
            receiver = "pushover";
            routes = [
              {
                group_wait = "30s";
                group_interval = "2m";
                repeat_interval = "4h";
                group_by = [ "alertname" "alias" ];
                receiver = "pushover";
              }
            ];
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
