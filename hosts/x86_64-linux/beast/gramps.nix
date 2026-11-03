{ config, lib, pkgs, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "gramps.${ext}";
  # Host loopback port nginx proxies to. The app listens on 5000 *inside* the
  # container (gunicorn, see upstream's Dockerfile); 5000 is a popular local dev
  # port on this workstation, so publish on 5055 instead.
  port = 5055;
  network = "gramps";
  # Backed-up state: the family tree (SQLite), the user DB (SQLite) and media.
  stateDir = "/var/lib/gramps";
  # Rebuildable caches: search index, thumbnails, report/export/flask caches and
  # the container's /tmp (large .gramps imports land there).
  cacheDir = "/var/cache/gramps";
  # kanidm lives on thunder and is only reachable through its nginx vhost. Pin
  # the name to thunder's tailscale IP via /etc/hosts instead of relying on
  # container DNS: beast has no static nameservers (resolved is off) and gets
  # thunder's unbound through tailscaled, which rewrites /etc/resolv.conf at will
  # — podman snapshots that file at container start, so a tailscale reconnect can
  # leave a long-running container unable to resolve auth.<domain>. That would
  # break OIDC discovery and the token/userinfo calls, which happen at login
  # time, long after the container started. Same fix as ha-mcp.nix. Using the
  # hostname (not the bare IP) keeps TLS SNI and the wildcard ACME cert valid.
  thunderIp = config.homelab.thunder.vlan.ip;
  # Pin explicitly — upstream ships only container images (the frontend is baked
  # into the same image as the API, served via GRAMPSWEB_STATIC_PATH), and there
  # is no nixpkgs package. The image uses calendar versioning; 26.11.0 is the
  # current release and :latest resolves to the same digest
  # (sha256:dbd20a8b…). Bump by hand.
  image = "ghcr.io/gramps-project/grampsweb:26.11.0";
  # Celery broker + flask-limiter storage. Upstream's compose uses valkey, the
  # redis fork, and talks to it over the redis protocol.
  redisImage = "docker.io/valkey/valkey:8-alpine";

  # Shared by the web and the celery container — upstream's compose gives them
  # the same environment and volumes via a YAML anchor, because both load the
  # whole app (the worker runs imports, exports, reports and reindexing against
  # the same tree).
  commonEnvironment = {
    # Display name of the tree. The container creates an empty tree with this
    # name on first start if none exists. TREE_ID (the on-disk directory name) is
    # deliberately unset — it can only be read back from the running instance via
    # GET /api/trees/-, and is only needed to rename the tree through the API.
    GRAMPSWEB_TREE = "Family Tree";
    # Public origin. The OIDC redirect_uri is built from this, so it has to match
    # the callback registered in kanidm byte for byte; it is also used for
    # password-reset links and Web Push.
    GRAMPSWEB_BASE_URL = "https://${domain}";
    # Celery queue + rate-limit storage, resolved by the --network-alias below.
    GRAMPSWEB_CELERY_CONFIG__broker_url = "redis://redis:6379/0";
    GRAMPSWEB_CELERY_CONFIG__result_backend = "redis://redis:6379/0";
    GRAMPSWEB_RATELIMIT_STORAGE_URI = "redis://redis:6379/1";
    # Don't phone home with usage statistics.
    GRAMPSWEB_DISABLE_TELEMETRY = "true";
    # No self-service sign-up. Redundant next to OIDC_DISABLE_LOCAL_AUTH below
    # (which closes registration by itself — a registered user could never log
    # in), but kept explicit so flipping local auth back on doesn't silently
    # reopen the sign-up form.
    GRAMPSWEB_REGISTRATION_DISABLED = "true";

    # --- Native OIDC against kanidm ---
    GRAMPSWEB_OIDC_ENABLED = "true";
    # kanidm's OIDC discovery is per-client: the app fetches
    # <issuer>/.well-known/openid-configuration, which kanidm only serves under
    # /oauth2/openid/<client_id>/ (same issuer shape readeck/paperless/healthlog
    # use). The container itself must be able to reach this URL, not just the
    # browser — it resolves auth.<domain> through beast's resolver like any other
    # podman container with the default DNS.
    GRAMPSWEB_OIDC_ISSUER = "https://auth.${ext}/oauth2/openid/gramps";
    GRAMPSWEB_OIDC_CLIENT_ID = "gramps";
    GRAMPSWEB_OIDC_NAME = "Kanidm";
    # kanidm requires PKCE for its clients. Gramps Web would normally turn PKCE
    # on by itself (it looks for S256 in the discovery document), but it silently
    # falls back to *no* PKCE if that fetch fails at login time — which kanidm
    # then rejects. Setting it explicitly removes that failure mode. Needs Gramps
    # Web API >= 3.23, which this image carries.
    GRAMPSWEB_OIDC_PKCE = "true";
    # Role mapping. Gramps Web reads the claim named here and picks the *highest*
    # matching role, so a user in several groups gets the strongest one. kanidm
    # emits these values from the `gramps` client's claimMaps.groups
    # (modules/nixos/kanidm.nix).
    #
    # Load-bearing: once any OIDC_GROUP_* is set, a user whose groups claim
    # matches *none* of them is set to the disabled role on every login
    # (fail-closed by design). That is why every member of gramps.access gets at
    # least `gramps-members`.
    #
    # Owner (not Admin) is the top role here: Admin is a site-wide role across
    # trees, Owner is the per-tree administrator that can manage this tree's
    # users — and upstream explicitly requires an owner/admin group to exist
    # before the first OIDC login, otherwise a fresh instance cannot be
    # bootstrapped (new OIDC accounts would all be created disabled, with nobody
    # able to approve them).
    GRAMPSWEB_OIDC_ROLE_CLAIM = "groups";
    GRAMPSWEB_OIDC_GROUP_OWNER = "gramps-owners";
    GRAMPSWEB_OIDC_GROUP_EDITOR = "gramps-editors";
    GRAMPSWEB_OIDC_GROUP_MEMBER = "gramps-members";
    # Full SSO: kanidm is the only way in, same stance as healthlog's OIDC_ONLY.
    # This makes POST /api/token/ (username + password) return 403 outright
    # (TokenResource.post in the app's source), and also closes registration on
    # its own. Two consequences worth knowing:
    #  - The Gramps *desktop* Gramps Web Sync addon can only authenticate with a
    #    username and password — it cannot complete an OIDC flow
    #    (DavidMStraub/gramps-web-sync#57, open) — so desktop→server sync is not
    #    possible while this is set. Importing/exporting .gramps files through
    #    the web UI still works.
    #  - There is no break-glass account: if kanidm/thunder is down, nobody can
    #    log in. (A site-admin account with no tree can't use OIDC login at all,
    #    so it isn't an escape hatch either.)
    GRAMPSWEB_OIDC_DISABLE_LOCAL_AUTH = "true";
    # With no password form left to show, send visitors straight to kanidm
    # instead of making them click the SSO button.
    GRAMPSWEB_OIDC_AUTO_REDIRECT = "true";

    # gunicorn forks this many workers, each of which loads Gramps and the tree.
    # Upstream defaults to 8; 4 is plenty for a handful of family users and keeps
    # the resident set on this workstation modest.
    GUNICORN_NUM_WORKERS = "4";
  };

  commonVolumes = [
    # --- backed up ---
    "${stateDir}/users:/app/users" # user DB (SQLite), incl. OIDC identities
    "${stateDir}/db:/root/.gramps/grampsdb" # the family tree itself (SQLite)
    "${stateDir}/media:/app/media" # media files (GRAMPSWEB_MEDIA_BASE_DIR)
    # --- rebuildable ---
    "${cacheDir}/indexdir:/app/indexdir" # search index (SQLite, reindexable)
    "${cacheDir}/thumbnail_cache:/app/thumbnail_cache"
    "${cacheDir}/cache:/app/cache" # report/export/request/persistent caches
    "${cacheDir}/tmp:/tmp" # import/export scratch space
  ];
in
{
  # Gramps Web = the Gramps genealogy database served over HTTP. Upstream ships
  # only container images, so this follows the healthlog pattern (podman +
  # oci-containers) rather than a NixOS module.
  #
  # Storage is SQLite throughout, which is upstream's default and needs no
  # configuration: the tree uses the `sqlite` Gramps backend (NEW_DB_BACKEND
  # defaults to "sqlite"), the user DB is sqlite:////app/users/users.sqlite and
  # the search index sqlite:////app/indexdir/search_index.db (both set as ENV in
  # the image). No Postgres container, and nothing in this file needs to say so —
  # it is simply what we get by not setting POSTGRES_*.

  # One agenix env file (root:root 0400) holding:
  #   GRAMPSWEB_SECRET_KEY — flask secret; changing it invalidates all issued
  #     tokens. Set explicitly rather than letting the entrypoint generate one
  #     into /app/secret, so there is no extra volume to persist and the value is
  #     backed up with the repo.
  #   GRAMPSWEB_OIDC_CLIENT_SECRET — the SAME raw secret kanidm serves as
  #     basicSecretFile from kanidm-oauth2-gramps.age on thunder; keep the two in
  #     sync when rekeying.
  # Both containers read it via --env-file.
  age.secrets.gramps-env.file = ../../../secrets/gramps-env.age;

  # The container runs as root (GRAMPSHOME=/root in the image) and rootful podman
  # maps that straight through, so these are plain root-owned dirs.
  #
  # On rpool1/safe/persist via impermanence: survives the root rollback and folds
  # into the ZFS-snapshot borg backup (modules/nixos/backup.nix) — no
  # gramps-specific job, same convention as every other stateful service. Gramps
  # Web's own BACKUP_DIR feature is deliberately left unset for the same reason.
  #
  # The three subdirectories are persisted individually (the paperless pattern)
  # so impermanence creates and bind-mounts each one, instead of relying on
  # tmpfiles to populate a freshly mounted, empty parent.
  environment.persistence."/persist".directories =
    let
      dir = directory: { inherit directory; mode = "0700"; };
    in
    [
      (dir stateDir)
      (dir "${stateDir}/users")
      (dir "${stateDir}/db")
      (dir "${stateDir}/media")
    ];

  # Caches go on /data/local (dpool, not backed up): the search index can be
  # rebuilt from the tree, thumbnails are regenerated on demand, and the rest is
  # scratch. Keeping them out of /persist keeps the borg set small.
  environment.persistence."/data/local".directories = [
    { directory = cacheDir; mode = "0700"; }
  ];

  # The image creates /app/cache/{reports,export,request_cache,persistent_cache}
  # at build time, but bind-mounting a host directory over /app/cache hides them.
  # REPORT_DIR / EXPORT_DIR are handed to Gramps as-is, so they have to exist
  # inside the mount — create them on the host side.
  systemd.tmpfiles.rules = map (d: "d ${d} 0700 root root -") [
    "${cacheDir}/indexdir"
    "${cacheDir}/thumbnail_cache"
    "${cacheDir}/cache"
    "${cacheDir}/cache/reports"
    "${cacheDir}/cache/export"
    "${cacheDir}/cache/request_cache"
    "${cacheDir}/cache/persistent_cache"
    "${cacheDir}/tmp"
  ];

  # podman itself and the /var/lib/containers image store are already configured
  # by ./healthlog.nix — do not re-declare them here.

  # oci-containers has no declarative network, and the default rootful "podman"
  # network gives no inter-container DNS. Create a user-defined network once
  # (idempotent) before the containers start, so the app and the worker resolve
  # the broker by name. Same shape as init-healthlog-network.
  systemd.services.init-gramps-network =
    let
      units = [ "podman-gramps.service" "podman-gramps-celery.service" "podman-gramps-redis.service" ];
    in
    {
      description = "Create the gramps podman network";
      wantedBy = units;
      before = units;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.podman}/bin/podman network exists ${network} \
          || ${pkgs.podman}/bin/podman network create ${network}
      '';
    };

  # Create the tree (and migrate the user DB) exactly once, before the web
  # container and the worker can race to do it.
  #
  # Why this is needed: the image's entrypoint runs
  # `python3 -m gramps_webapi … user migrate`, whose CLI builds the Flask app
  # (`__main__.py`: `ctx.obj = {"app": create_app()}`), and `create_app()` in a
  # single-tree setup constructs `WebDbManager(name = TREE,
  # create_if_missing = true)`. A tree is looked up by *display name*, so on an
  # empty `/persist` both containers find no "Family Tree", and both create one —
  # two directories (uuid4 names) carrying the same name.txt. From then on
  # `CLIDbManager.get_family_tree_path(name)` resolves the name to whichever it
  # finds first, so the web app and the worker can end up opening *different*
  # SQLite files. Observed on the very first boot: two trees, same timestamp.
  #
  # `TREE_ID` (identify the tree by directory name) would also fix the ambiguity,
  # but it can't bootstrap: with `TREE_ID` set, `create_app()` passes
  # create_if_missing = false, so the tree has to exist already.
  #
  # Running the image with `true` as the command is enough — the entrypoint does
  # the migration and the tree creation before exec'ing it. Idempotent, and
  # RemainAfterExit keeps it from re-running when a container restarts.
  systemd.services.gramps-bootstrap =
    let
      envFlags = lib.mapAttrsToList (k: v: "-e ${lib.escapeShellArg "${k}=${v}"}") commonEnvironment;
      volumeFlags = map (v: "-v ${v}") commonVolumes;
    in
    {
      description = "Bootstrap the Gramps tree and user DB (once, before app and worker)";
      wantedBy = [ "podman-gramps.service" "podman-gramps-celery.service" ];
      before = [ "podman-gramps.service" "podman-gramps-celery.service" ];
      # Attached to the gramps network so the redis URLs in the environment
      # resolve during app init, exactly as they do for the real containers.
      after = [ "init-gramps-network.service" "podman-gramps-redis.service" ];
      wants = [ "podman-gramps-redis.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.podman}/bin/podman run --rm --name gramps-bootstrap \
          --network=${network} \
          --env-file ${config.age.secrets.gramps-env.path} \
          ${lib.concatStringsSep " \\\n  " (envFlags ++ volumeFlags)} \
          ${image} true
      '';
    };

  virtualisation.oci-containers.containers = {
    # Broker for the celery worker (queue + results) and storage for
    # flask-limiter's rate limits. Pure cache: nothing here needs to survive a
    # restart, so it gets no volume.
    gramps-redis = {
      image = redisImage;
      networks = [ network ];
      extraOptions = [ "--network-alias=redis" ];
    };

    # Web (gunicorn) + the bundled static frontend.
    gramps = {
      inherit image;
      dependsOn = [ "gramps-redis" ];
      environmentFiles = [ config.age.secrets.gramps-env.path ];
      environment = commonEnvironment;
      volumes = commonVolumes;
      ports = [ "127.0.0.1:${toString port}:5000" ];
      networks = [ network ];
      # See the thunderIp note at the top: the OIDC flow runs from inside this
      # container, so auth.<domain> has to stay resolvable for the lifetime of
      # the container, not just at start.
      extraOptions = [ "--add-host=auth.${ext}:${thunderIp}" ];
    };

    # Background tasks: imports, exports, reports, reindexing, media processing.
    # Same image and volumes as the web container, no published port. Ordered
    # after the web container because that one's entrypoint runs the user-DB
    # migration (`gramps_webapi user migrate`).
    gramps-celery = {
      inherit image;
      cmd = [ "celery" "-A" "gramps_webapi.celery" "worker" "--loglevel=INFO" "--concurrency=2" ];
      dependsOn = [ "gramps-redis" "gramps" ];
      environmentFiles = [ config.age.secrets.gramps-env.path ];
      environment = commonEnvironment;
      volumes = commonVolumes;
      networks = [ network ];
    };
  };

  # VPN-only by DNS: gramps.<domain> is served only by thunder's unbound to VPN
  # clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record, and
  # beast is not publicly reachable — so no allow/deny block, same as
  # readeck/healthlog. Gramps Web runs the OIDC flow itself, so no oauth2-proxy
  # gate on top — that would double up on auth and break every non-browser API
  # client, which cannot complete an interactive cookie flow.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    extraConfig = ''
      # Media uploads and whole-tree .gramps / media-archive imports.
      client_max_body_size 1024M;
      # Importing a large tree or building a media archive keeps the request open
      # well past nginx's 60s default (gunicorn itself allows 120s per request).
      proxy_read_timeout 300s;
      proxy_send_timeout 300s;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
    };
  };
}
