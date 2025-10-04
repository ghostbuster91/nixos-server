{ config, ... }:
{

  services.promtail = {
    enable = true;
    configuration = {
      server = {
        disable = true;
      };
      clients = [{
        url = "https://loki.${config.homelab.ext-domain}/loki/api/v1/push";
      }];
      scrape_configs = [{
        job_name = "journal";
        journal = {
          max_age = "12h";
          labels = {
            job = "systemd-journal";
            host = config.networking.hostName;
          };
        };
        relabel_configs = [{
          source_labels = [ "__journal__systemd_unit" ];
          target_label = "unit";
        }];
      }];
    };
  };
}
