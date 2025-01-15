{ config, ... }:
{

  services.promtail = {
    enable = true;
    configuration = {
      server = {
        disable = true;
      };
      clients = [{
        url = "https://loki.local/loki/api/v1/push";
        # TODO validate against the real certificate
        # This needs correct Subject Alternative Name to be assigned which needs subdomains 
        # which needs moving to a public domain
        tls_config.insecure_skip_verify = true;
      }];
      scrape_configs = [{
        job_name = "journal";
        journal = {
          max_age = "12h";
          labels = {
            job = "systemd-journal";
            host = config.homelab.hostname;
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
