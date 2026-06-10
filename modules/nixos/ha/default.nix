{ config, ... }:
let
  roleName = "ha";
in
{
  environment.persistence."/persist".directories = [
    {
      directory = config.services.home-assistant.configDir;
      user = "hass";
      group = "hass";
      mode = "0700";
    }
  ];
  systemd.services.nginx = {
    requires = [ "home-assistant.service" ];
  };
  nixpkgs.config.permittedInsecurePackages = [
    "openssl-1.1.1w"
  ];

  # TODO: infinite recursion for rpi5 eval
  # topology.self.services.home-assistant.info = "https://${roleName}.${config.homelab.ext-domain}";
  services.home-assistant =
    let
      # Components required to complete the onboarding
      onboardingRequiredComponents = [
        "analytics"
        "google_translate"
        "met"
        "radio_browser"
        "shopping_list"
        "roborock" # non-deterministic build process (sometimes fails)
        "smlight"
        "cast"
        "ipp"
      ];
    in
    {
      enable = true;
      extraComponents = onboardingRequiredComponents ++ [
        "prometheus"
        "mqtt"
        # "spotify"
        # "tts"
        # "my"
        # Recommended for fast zlib compression
        "isal"
        "esphome"
        "aws_s3"
        "shelly"
        "tedee"
        "wyoming"
      ];
      config = {
        # Includes dependencies for a basic setup
        # https://www.home-assistant.io/integrations/default_config/
        default_config = { };
        http = {
          server_host = [ "::1" ];
          trusted_proxies = [ "::1" ];
          use_x_forwarded_for = true;
        };
        prometheus = { };
        automation = [
          {
            alias = "Lock front door at 23:00";
            trigger = [{
              platform = "time";
              at = "23:00:00";
            }];
            action = [{
              service = "lock.lock";
              target.entity_id = "lock.drzwi_glowne";
            }];
          }
          {
            alias = "Re-lock front door if left unlocked at night";
            trigger = [{
              platform = "state";
              entity_id = "lock.drzwi_glowne";
              to = "unlocked";
              for = "00:10:00";
            }];
            condition = [{
              condition = "time";
              after = "23:00:00";
              before = "06:00:00";
            }];
            action = [{
              service = "lock.lock";
              target.entity_id = "lock.drzwi_glowne";
            }];
          }
        ];
        mqtt = {
          sensor = [
            {
              device_class = "temperature";
              name = "Czujnik sypialnia";
              state_topic = "ampio/from/1C60E/state/t/1";
              state_class = "measurement";
              unique_id = "ampio_bedroom_temp";
              unit_of_measurement = "°C";
            }
            {
              device_class = "temperature";
              name = "Czujnik łazienka";
              state_topic = "ampio/from/1B6B0/state/t/1";
              state_class = "measurement";
              unique_id = "ampio_bathroom_temp";
              unit_of_measurement = "°C";
            }
            {
              device_class = "temperature";
              name = "Czujnik pralnia";
              state_topic = "ampio/from/1C5F3/state/t/1";
              state_class = "measurement";
              unique_id = "ampio_laundry_temp";
              unit_of_measurement = "°C";
            }
            {
              device_class = "temperature";
              name = "Czujnik gabinet";
              state_topic = "ampio/from/1C6ED/state/t/1";
              state_class = "measurement";
              unique_id = "ampio_study_temp";
              unit_of_measurement = "°C";
            }
            {
              device_class = "temperature";
              name = "Czujnik salon";
              state_topic = "ampio/from/1C625/state/t/1";
              state_class = "measurement";
              unique_id = "ampio_livingroom_temp";
              unit_of_measurement = "°C";
            }
          ];
        };
      };
    };

  services.nginx.virtualHosts."${roleName}.${config.homelab.ext-domain}" = {
    useACMEHost = config.homelab.ext-domain;
    forceSSL = true;

    extraConfig = ''
      proxy_buffering off;
    '';
    locations."/" = {
      proxyPass = "http://[::1]:${toString config.services.home-assistant.config.http.server_port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
