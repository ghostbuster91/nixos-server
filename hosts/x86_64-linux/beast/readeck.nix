{ config, pkgs-unstable, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "readeck.${ext}";
  port = 8090;
in
{
  # Env file (root:root 0400) holding READECK_SECRET_KEY and the raw OIDC client
  # secret as READECK_AUTH_OIDC_PROVIDERS_0_CLIENT_SECRET. The same client secret
  # value also lives in kanidm-oauth2-readeck.age (kanidm's basicSecretFile on
  # thunder); keep the two in sync when rekeying.
  age.secrets.readeck-env.file = ../../../secrets/readeck-env.age;

  # readeck 0.23 (native OIDC) only landed in unstable; the stable module/package
  # predate it. Pull the package from pkgs-unstable; the module shape is the same.
  services.readeck = {
    enable = true;
    package = pkgs-unstable.readeck;

    # The OIDC client secret and READECK_SECRET_KEY are NOT set in `settings`:
    # the module renders `settings` into a config.toml that is copied from the
    # world-readable Nix store, so any secret there would leak. They come in via
    # this EnvironmentFile instead (agenix-decrypted, root-owned 0400). systemd
    # reads it as PID 1 before dropping to readeck's DynamicUser. The env var
    # READECK_AUTH_OIDC_PROVIDERS_0_CLIENT_SECRET overrides client_secret of the
    # first (index 0) provider entry defined in settings below.
    environmentFile = config.age.secrets.readeck-env.path;

    settings = {
      server = {
        host = "127.0.0.1";
        inherit port;
        # Pin the public origin. With base_url set, readeck treats it as the only
        # valid URL of the instance and builds the OIDC redirect_uri from it —
        # https://readeck.<domain>/login/oidc — instead of inferring it from
        # request headers, so it always matches the callback registered in kanidm
        # (kanidm.nix). nginx is the only path in and terminates TLS.
        base_url = "https://${domain}";
        allowed_hosts = [ domain ];
        # nginx runs on the same host and reverse-proxies over loopback; trust it
        # so X-Forwarded-* (proto/for) from 127.0.0.1 are honoured.
        trusted_proxies = [ "127.0.0.1" ];
      };

      # Native OIDC against kanidm. A single provider makes readeck show only the
      # "Sign in with Kanidm" button. The client_secret is injected at runtime
      # via environmentFile (see above), so it is intentionally absent here.
      # Callback URL registered in kanidm is https://<domain>/login/oidc.
      auth.oidc.providers = [
        {
          name = "Kanidm";
          # kanidm's OIDC discovery is per-client, not at the server root:
          # readeck fetches <url>/.well-known/openid-configuration, and kanidm
          # only serves that under /oauth2/openid/<client_id>/ (a bare auth.<domain>
          # returns "404 Route not found"). This is the same per-client issuer
          # paperless (server_url) and dashy (endpoint) point at.
          url = "https://auth.${ext}/oauth2/openid/readeck";
          client_id = "readeck";
          # Auto-create the readeck account on first SSO login. Membership in
          # readeck.access is the real gate (kanidm won't authorize the scopes
          # for a non-member), so provisioning can't create accounts for people
          # outside the group.
          provisioning = true;
          # Map kanidm's `groups` claim (emitted by kanidm.nix's readeck claim
          # map as readeck-admin / readeck-user) onto readeck's own roles. First
          # match wins, so admins listed first.
          groups = [
            [ "readeck-admin" "admin" ]
            [ "readeck-user" "user" ]
          ];
        }
      ];
    };
  };

  # readeck's SQLite db, the bookmark article store and the bleve search index
  # live under the module's StateDirectory=readeck. It runs under DynamicUser, so
  # systemd materialises that at /var/lib/private/readeck (and symlinks
  # /var/lib/readeck -> it); persist that real path — the same DynamicUser
  # convention as mealie, ntfy, esphome, open-webui and atticd. systemd
  # re-chowns it to the dynamic UID on start, so no user/group is set here. On
  # rpool1/safe/persist it survives the root rollback and folds into the
  # ZFS-snapshot borg backup (backup.nix) — no readeck-specific job.
  environment.persistence."/persist".directories = [
    { directory = "/var/lib/private/readeck"; mode = "0700"; }
  ];

  # VPN-only by DNS: readeck.<domain> is served only by thunder's unbound to VPN
  # clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record.
  # Unlike thunder's public-facing vhosts this needs no allow/deny block — beast
  # is not publicly reachable. readeck does its own OIDC, so no oauth2-proxy gate.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    extraConfig = ''
      client_max_body_size 64M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
