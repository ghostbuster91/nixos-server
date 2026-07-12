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
        # OIDC/SSO auth provider (kanidm). Same python-set reasoning as above.
        (pkgs.callPackage ./oidc-auth.nix {
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
        # Disable the built-in username/password login provider — only OIDC
        # (auth_oidc, injected by the custom component) remains. NOTE: if kanidm
        # is unreachable this locks everyone out; recovery is to revert this line
        # and redeploy. https://github.com/christiaangoossens/hass-oidc-auth/discussions/67
        homeassistant.auth_providers = [ ];
        http = {
          server_host = [ "::1" ];
          trusted_proxies = [ "::1" ];
          use_x_forwarded_for = true;
        };
        # OIDC/SSO login via kanidm (auth_oidc custom component). Public PKCE
        # client — no secret. Kanidm signs id_tokens with ES256. Roles map the
        # raw kanidm group SPNs from the "groups" claim: members of ha.access get
        # the "user" role, ha.admins get "admin". The kanidm oauth2 client
        # `homeassistant` is provisioned on thunder (modules/nixos/kanidm.nix).
        auth_oidc = {
          client_id = "homeassistant";
          discovery_url = "https://auth.${config.homelab.ext-domain}/oauth2/openid/homeassistant/.well-known/openid-configuration";
          id_token_signing_alg = "ES256";
          roles = {
            admin = "ha.admins@${config.homelab.ext-domain}";
            user = "ha.access@${config.homelab.ext-domain}";
          };
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
