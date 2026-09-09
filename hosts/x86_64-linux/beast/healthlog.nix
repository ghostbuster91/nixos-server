{ config, pkgs, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "healthlog.${ext}";
  # Host loopback port nginx proxies to. The app listens on 3000 *inside* the
  # container, but 3000 is Grafana and 3100 is Loki on beast, so publish on 3005.
  port = 3005;
  network = "healthlog";
  # Postgres data dir on the host, bind-mounted into the db container.
  dbDir = "/var/lib/healthlog-db";
  # Pin both images explicitly (upstream only ships Docker images — there is no
  # native build). Bump the app tag by hand; the 16-alpine Postgres matches the
  # version upstream's compose ships.
  appImage = "ghcr.io/mbombeck/healthlog:1.38.11";
  dbImage = "postgres:16-alpine";
in
{
  # One agenix env file (root:root 0400) holding every HealthLog secret:
  #   POSTGRES_PASSWORD, ENCRYPTION_KEY, API_TOKEN_HMAC_KEY, DATABASE_URL and
  #   OIDC_CLIENT_SECRET. Both containers read it via --env-file; the extra vars
  #   the Postgres image doesn't recognise are simply ignored. DATABASE_URL
  #   embeds POSTGRES_PASSWORD, so it has to live here rather than in the
  #   world-readable Nix store `environment` below. The OIDC_CLIENT_SECRET value
  #   is the SAME raw secret kanidm serves as basicSecretFile from
  #   kanidm-oauth2-healthlog.age on thunder — keep the two in sync when rekeying.
  age.secrets.healthlog-env.file = ../../../secrets/healthlog-env.age;

  # Postgres data dir. postgres:16-alpine runs as uid/gid 70; rootful podman maps
  # that straight through, so the host dir must be owned 70:70 (tmpfiles below,
  # since no host user owns 70). On rpool1/safe/persist it survives the
  # impermanence root rollback and folds into the ZFS-snapshot borg backup
  # (backup.nix) — no healthlog-specific job, same convention as every other
  # stateful service. The app container itself is stateless (all state is in PG).
  environment.persistence."/persist".directories = [
    { directory = dbDir; mode = "0700"; }
  ];
  # Empty marker file bind-mounted to /.dockerenv in the app container (below).
  # HealthLog's prisma.config.ts detects "am I containerised?" via
  # `fs.existsSync("/.dockerenv")` — a file Docker creates but **podman does
  # not** (podman uses /run/.containerenv). Without it HealthLog assumes a
  # host-local Prisma CLI, rewrites the DATABASE_URL host `db` → `localhost`
  # for `migrate deploy`, and the migration fails with P1001 (no Postgres at
  # localhost in the app container). Presenting /.dockerenv makes the detection
  # behave as upstream intends.
  systemd.tmpfiles.rules = [
    "d ${dbDir} 0700 70 70 -"
    "f /var/lib/healthlog-dockerenv 0444 root root -"
  ];

  # Image + layer store. Reproducible (re-pullable), so it goes on /data/local
  # (dpool, not backed up) rather than bloating the borg set.
  environment.persistence."/data/local".directories = [
    "/var/lib/containers"
  ];

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # oci-containers has no declarative network, and the default rootful "podman"
  # network gives no inter-container DNS. Create a user-defined network once
  # (idempotent) before the containers start so the app resolves the database by
  # name. The db container takes the alias `db` so the upstream-shaped
  # DATABASE_URL (…@db:5432/…) in the env file resolves unchanged.
  systemd.services.init-healthlog-network = {
    description = "Create the healthlog podman network";
    wantedBy = [ "podman-healthlog.service" "podman-healthlog-db.service" ];
    before = [ "podman-healthlog.service" "podman-healthlog-db.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.podman}/bin/podman network exists ${network} \
        || ${pkgs.podman}/bin/podman network create ${network}
    '';
  };

  virtualisation.oci-containers.containers = {
    healthlog-db = {
      image = dbImage;
      environmentFiles = [ config.age.secrets.healthlog-env.path ];
      environment = {
        POSTGRES_USER = "healthlog";
        POSTGRES_DB = "healthlog";
      };
      volumes = [ "${dbDir}:/var/lib/postgresql/data" ];
      networks = [ network ];
      extraOptions = [ "--network-alias=db" ];
    };

    healthlog = {
      image = appImage;
      # Orders the app unit after the db unit. Postgres being *started* isn't the
      # same as *ready*; the app's entrypoint runs Prisma migrations on boot and
      # exits if the DB isn't up yet, but the unit's default Restart=on-failure
      # retries until Postgres accepts connections.
      dependsOn = [ "healthlog-db" ];
      environmentFiles = [ config.age.secrets.healthlog-env.path ];
      environment = {
        NODE_ENV = "production";
        # Public origin. nginx terminates TLS, so NODE_ENV=production makes the
        # session cookie Secure automatically (SESSION_COOKIE_SECURE left unset).
        APP_URL = "https://${domain}";
        NEXT_PUBLIC_APP_URL = "https://${domain}";
        # nginx is the single proxy hop in front; read the real client IP from
        # the last X-Forwarded-For entry so rate-limiting isn't collapsed.
        TRUST_PROXY_HOPS = "1";
        # Bundle web + worker in this one container (single-host default).
        HEALTHLOG_PROCESS_TYPE = "all";
        # Full SSO: disable local password/passkey sign-in and force kanidm OIDC,
        # keeping HealthLog behind the IdP like the rest of the fleet. Membership
        # in healthlog.access (kanidm.nix) is the real gate. The first user to
        # sign in via SSO becomes the admin.
        OIDC_ONLY = "true";
        # kanidm's OIDC discovery is per-client: HealthLog fetches
        # <issuer>/.well-known/openid-configuration, which kanidm only serves
        # under /oauth2/openid/<client_id>/ (same issuer readeck/paperless use).
        OIDC_ISSUER_URL = "https://auth.${ext}/oauth2/openid/healthlog";
        OIDC_CLIENT_ID = "healthlog";
        OIDC_BUTTON_LABEL = "Kanidm";
        # OIDC_CLIENT_SECRET comes from the env file above.
      };
      # See the tmpfiles note above: fake Docker's /.dockerenv so HealthLog's
      # container detection works under podman and doesn't rewrite `db` →
      # `localhost` for the boot-time Prisma migration.
      volumes = [ "/var/lib/healthlog-dockerenv:/.dockerenv:ro" ];
      ports = [ "127.0.0.1:${toString port}:3000" ];
      networks = [ network ];
    };
  };

  # VPN-only by DNS: healthlog.<domain> is served only by thunder's unbound to
  # VPN clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record.
  # Like readeck (and unlike thunder's public vhosts) it needs no allow/deny
  # block — beast is not publicly reachable. HealthLog does its own OIDC, so no
  # oauth2-proxy gate — which would also break its native iOS client and API
  # tokens. 64M body limit covers photo / PDF doctor-report uploads.
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
