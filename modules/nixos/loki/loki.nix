{ config, ... }:
let
  roleName = "loki";
  port_loki = 8084;
in
{
  # networking.firewall.allowedTCPPorts = [
  #   port_loki
  # ];


  # remedy for no usable address found on interface..
  systemd.services.loki = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };
  services = {
    loki = {
      enable = true;
      configuration = {
        server.http_listen_port = port_loki;
        auth_enabled = false;

        common = {
          instance_interface_names = [
            "enp3s0"
          ];
        };
        ingester = {
          lifecycler = {
            address = "127.0.0.1";
            ring = {
              kvstore = {
                store = "inmemory";
              };
              replication_factor = 1;
            };
          };
          chunk_idle_period = "1h";
          max_chunk_age = "1h";
          chunk_target_size = 999999;
          chunk_retain_period = "30s";
          query_store_max_look_back_period = "0s";
        };

        schema_config = {
          configs = [
            {
              from = "2024-06-23";
              store = "tsdb";
              object_store = "filesystem";
              schema = "v13";
              index = {
                prefix = "index_";
                period = "24h";
              };
            }
          ];
        };

        storage_config = {
          tsdb_shipper = {
            active_index_directory = "/var/lib/loki/tsdb-shipper-active";
            cache_location = "/var/lib/loki/tsdb-shipper-cache";
            cache_ttl = "24h";
          };

          filesystem = {
            directory = "/var/lib/loki/chunks";
          };
        };

        limits_config = {
          reject_old_samples = true;
          reject_old_samples_max_age = "168h";
        };


        table_manager = {
          retention_deletes_enabled = false;
          retention_period = "0s";
        };

        compactor = {
          working_directory = "/var/lib/loki";
          delete_request_store = "filesystem";
          compactor_ring = {
            kvstore = {
              store = "inmemory";
            };
          };
        };
      };
    };

    nginx.enable = true;
    nginx.virtualHosts."${roleName}.${config.homelab.domain}" = {
      # Use wildcard domain
      # useACMEHost = config.homelab.domain;
      serverName = "${roleName}.${config.homelab.domain}";
      forceSSL = false;

      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port_loki}";
        proxyWebsockets = true;
        recommendedProxySettings = true;
      };
    };
  };
}
