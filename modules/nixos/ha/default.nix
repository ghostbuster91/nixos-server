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

  nixpkgs.overlays = [
    (_final: prev: {
      # ./ezviz-cloud.nix pins pyezvizapi ==1.0.5.0 in its manifest, and
      # buildHomeAssistantComponent *enforces* manifest requirements
      # (manifest-requirements-check-hook), so 26.05's 1.0.4.9 fails the build.
      # 1.0.5.0 also dropped the pandas dependency, hence the trimmed list.
      #
      # Nothing else in this config uses pyezvizapi: the built-in `ezviz`
      # component is out of extraComponents below. (It needed a patch to cope
      # with this same bump — upstream home-assistant commit 0b831ef02 — which
      # was dropped once its config entry was deleted. Restore it from git
      # history if the built-in component ever comes back.)
      #
      # Done via pythonPackagesExtensions rather than
      # `python314.override { packageOverrides = … }` on purpose: malina5's
      # custom.nix already uses that argument, and `.override` *replaces* it
      # rather than composing, so a second one would silently drop the aarch64
      # test-flake fixes there.
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (pyfinal: pyprev: {
          pyezvizapi = pyprev.pyezvizapi.overridePythonAttrs (_old: rec {
            version = "1.0.5.0";
            src = prev.fetchFromGitHub {
              owner = "RenierM26";
              repo = "pyEzvizApi";
              tag = "v${version}";
              hash = "sha256-m3rj8ELu8/X/3TPtC1wfN8VOs7eHKb4DNvb7JAoKXfE=";
            };
            dependencies = with pyfinal; [
              paho-mqtt
              pycryptodome
              requests
              xmltodict
            ];
          });
        })
      ];
    })
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
        # "Ezviz(Beta)" (domain ezviz_cloud) — cloud images/clips/push for the
        # HP2 peephole, which has no RTSP for the built-in ezviz to talk to.
        # This replaces the built-in `ezviz`, which is out of extraComponents
        # below and whose config entry was deleted on 2026-10-22. Note that
        # dropping a component from extraComponents only removes its *deps*
        # from the service PYTHONPATH — the component's files still ship inside
        # the home-assistant package, and this component propagates pyezvizapi
        # anyway — so re-adding an `ezviz` entry in the UI would still load it,
        # duplicating every entity (second set lands as `*_2`).
        # Same python-set reasoning as above.
        (pkgs.callPackage ./ezviz-cloud.nix {
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
        "bthome"
        "rest_command"
        # "ezviz" — superseded by the ezviz_cloud custom component above.
        "shelly"
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
        # ntfy push used by the "notify if front door unlocked at 23:00"
        # automation. ntfy runs on this same host (malina5), so this POST to
        # ntfy.<ext-domain> resolves to malina5's own tailscale IP and stays
        # local (no tailnet hop, no ACL). The wildcard ACME cert on
        # ntfy.<ext-domain> makes aiohttp's TLS verification pass.
        rest_command.ntfy_front_door = {
          url = "https://ntfy.${config.homelab.ext-domain}/homelab";
          method = "POST";
          content_type = "text/plain; charset=utf-8";
          payload = "Front door is still unlocked at 23:00.";
          headers = {
            Title = "Lock the front door";
            Priority = "high";
            Tags = "lock,house";
          };
        };
        # Generic ntfy push: the caller supplies title/message/priority/tags as
        # service-call data (see `mkHighAlert` in ./automations.nix). Same topic
        # and locality reasoning as ntfy_front_door above.
        # Keep titles/tags ASCII — ntfy sends them as HTTP headers; the body
        # (payload) is UTF-8 and may contain Polish characters.
        rest_command.ntfy = {
          url = "https://ntfy.${config.homelab.ext-domain}/homelab";
          method = "POST";
          content_type = "text/plain; charset=utf-8";
          payload = "{{ message }}";
          headers = {
            Title = "{{ title | default('Home Assistant', true) }}";
            Priority = "{{ priority | default('default', true) }}";
            Tags = "{{ tags | default('house', true) }}";
          };
        };
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
