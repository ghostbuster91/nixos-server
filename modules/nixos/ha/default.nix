{ config, pkgs, ... }:
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
      customComponents = [
        # Build against Home Assistant's own Python set (26.05 -> 3.14) so the
        # component and its deps match; the default pkgs.python3Packages is 3.13
        # and trips the module's python-version-match assertion.
        (pkgs.callPackage ./hon.nix {
          python3Packages = config.services.home-assistant.package.python3Packages;
        })
      ];
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
        "ollama"
        "satel_integra"
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
        automation = import ./automations.nix;
        mqtt = {
          sensor = import ./mqtt_sensors.nix;
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
