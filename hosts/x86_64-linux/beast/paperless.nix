{ config, lib, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "paperless.${ext}";
  port = 28981;
  dataDir = "/var/lib/paperless";

  # allauth OpenID-Connect provider config, serialised to the JSON that paperless
  # expects in PAPERLESS_SOCIALACCOUNT_PROVIDERS. The client secret is NOT baked
  # in here — the paperless module renders `settings` into the systemd unit's
  # Environment= (world-readable in the Nix store), so @SECRET@ is a placeholder
  # swapped for the real value at runtime by paperless-oidc-config.service below.
  socialProviders = builtins.toJSON {
    openid_connect = {
      # kanidm requires PKCE by default; allauth performs it when this is set.
      OAUTH_PKCE_ENABLED = true;
      APPS = [
        {
          provider_id = "kanidm";
          name = "Kanidm";
          client_id = "paperless";
          secret = "@SECRET@";
          settings.server_url =
            "https://auth.${ext}/oauth2/openid/paperless/.well-known/openid-configuration";
        }
      ];
    };
  };
in
{
  # Raw OIDC client secret (bare value, no env prefix). The same secret also
  # lives in kanidm-oauth2-paperless.age (kanidm's basicSecretFile on thunder);
  # keep the two in sync.
  age.secrets.paperless-oidc-secret.file = ../../../secrets/paperless-oidc-secret.age;

  # dataDir holds the SQLite db, search index, media (originals + archive) and
  # the consume dir. It lives on rpool1/safe/persist via impermanence, so it
  # survives the root rollback and is captured by the ZFS-snapshot borg backup
  # (modules/nixos/backup.nix) — no paperless-specific export job is needed, the
  # same convention as kanidm/vaultwarden/mealie.
  environment.persistence."/persist".directories = [
    {
      directory = dataDir;
      user = "paperless";
      group = "paperless";
      mode = "0700";
    }
  ];

  services.paperless = {
    enable = true;
    address = "127.0.0.1";
    inherit port dataDir;

    settings = {
      # Public origin. paperless appends this to ALLOWED_HOSTS / CSRF_TRUSTED_ORIGINS.
      PAPERLESS_URL = "https://${domain}";
      # nginx terminates TLS and forwards X-Forwarded-Proto; trusting it makes
      # paperless build an https:// OIDC redirect_uri that matches what kanidm
      # has registered (otherwise the callback would be http:// and be rejected).
      PAPERLESS_PROXY_SSL_HEADER = builtins.toJSON [ "HTTP_X_FORWARDED_PROTO" "https" ];

      # OCR both Polish and English documents (tesseract data is pulled in
      # automatically from this list).
      PAPERLESS_OCR_LANGUAGE = "pol+eng";

      # --- Native OIDC (django-allauth) against kanidm ---
      PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
      # PAPERLESS_SOCIALACCOUNT_PROVIDERS is injected at runtime (with the real
      # secret) via the EnvironmentFile on paperless-web, not set here.
      PAPERLESS_SOCIAL_AUTO_SIGNUP = true; # create the paperless user on first SSO login
      PAPERLESS_SOCIALACCOUNT_ALLOW_SIGNUPS = true; # ...but only via SSO
      PAPERLESS_ACCOUNT_ALLOW_SIGNUPS = false; # no self-service local accounts
      PAPERLESS_REDIRECT_LOGIN_TO_SSO = true; # skip the native login page
    };
  };

  # Render PAPERLESS_SOCIALACCOUNT_PROVIDERS with the client secret substituted
  # in, into a root-owned 0600 file that systemd (as PID 1) reads before dropping
  # to the paperless user. Kept out of `settings` so the secret never lands in
  # the Nix store. Runs as a separate oneshot so the file exists before
  # paperless-web reads its EnvironmentFile (an ExecStartPre in the same unit
  # would be too late — EnvironmentFile is read at unit activation).
  systemd.services.paperless-oidc-config = {
    description = "Render paperless OIDC provider config (injects the client secret)";
    wantedBy = [ "multi-user.target" ];
    before = [ "paperless-web.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "paperless-oidc";
      RuntimeDirectoryMode = "0700";
      LoadCredential = "secret:${config.age.secrets.paperless-oidc-secret.path}";
    };
    script = ''
      secret=$(cat "$CREDENTIALS_DIRECTORY/secret")
      providers=${lib.escapeShellArg socialProviders}
      umask 0077
      # Single-quote the JSON so systemd passes it literally; the secret is
      # alphanumeric, so it can't break out of the quotes.
      printf "PAPERLESS_SOCIALACCOUNT_PROVIDERS='%s'\n" "''${providers//@SECRET@/$secret}" \
        > "$RUNTIME_DIRECTORY/env"
    '';
  };

  systemd.services.paperless-web = {
    after = [ "paperless-oidc-config.service" ];
    requires = [ "paperless-oidc-config.service" ];
    serviceConfig.EnvironmentFile = "/run/paperless-oidc/env";
  };

  # VPN-only by DNS: paperless.<domain> is served only by thunder's unbound to
  # VPN clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record.
  # Unlike thunder's vaultwarden vhost this needs no allow/deny block — beast is
  # not publicly reachable.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    extraConfig = ''
      client_max_body_size 128M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
