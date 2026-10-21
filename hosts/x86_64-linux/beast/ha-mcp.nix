{ config, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "ha-mcp.${ext}";
  # Host loopback port nginx proxies to. 8086 is also the container-internal
  # default (ha-mcp-web), so no remap needed — nothing else on beast uses it.
  port = 8086;
  # Settings/data dir on the host, bind-mounted into the container.
  dataDir = "/var/lib/ha-mcp";
  # Dedicated host identity for the container process, overriding the image's own
  # user. That user is uid 999 (Dockerfile: `useradd -r -u 999 mcpuser`), and
  # rootful podman maps container uids straight through — but on beast 999 is
  # `dhcpcd`, an active, network-facing daemon. Reusing it would put ha-mcp's
  # data dir (OAuth client registrations) and /var/lib/dhcpcd under one shared
  # account, each writable by the other. The image is explicitly built to accept
  # a `--user` override instead: its Dockerfile keeps /home/mcpuser at 0755 and
  # sets HOME as an ENV precisely so a foreign uid can still resolve
  # HOME-relative paths (their issue #1125).
  #
  # These must be literals: a bind-mounted dir records numeric ownership, and
  # NixOS only allocates `isSystemUser` ids at activation time, so the value is
  # not readable from Nix. 600 is clear at both ends — nixpkgs' ids.nix declares
  # nothing in 400-999, and NixOS's dynamic system-user allocator descends from
  # 999 (lowest in use here is 981), so it will not reach 600 for a very long
  # time and skips explicitly declared ids regardless.
  uid = 600;
  gid = 600;
  # Pin explicitly — upstream ships only container images / PyPI wheels, and the
  # PyPI route is not viable here (see the comment block below). 8.7.0 is the
  # current stable; :latest and :stable both resolve to the same digest
  # (sha256:600677bb…). Bump by hand.
  image = "ghcr.io/homeassistant-ai/ha-mcp:8.7.0";
  # Home Assistant lives on malina5 and binds ::1 only, so the only way in is
  # its nginx vhost. Pin the name to malina5's tailscale IP via /etc/hosts
  # instead of relying on container DNS: beast has no static nameservers
  # (resolved is off) and gets thunder's unbound through tailscaled, which
  # rewrites /etc/resolv.conf at will — podman snapshots that file at container
  # start, so a tailscale reconnect can leave the container unable to resolve
  # ha.<domain>. Using the hostname (not the bare IP) keeps TLS SNI and the
  # wildcard ACME cert valid.
  malina5Ip = config.homelab.malina5.vlan.ip;
in
{
  # ha-mcp is the unofficial full-fat Home Assistant MCP server (87 tools:
  # automations, dashboards, backups, registry, HACS, …). Upstream's recommended
  # install is the `ha_mcp_tools` custom component via HACS, which is NOT usable
  # here: the nixpkgs home-assistant wrapper runs `hass --skip-pip`, so a
  # component's manifest `requirements` are never installed and must come from
  # Nix. That manifest pins `ha-mcp-dev==9.0.0.dev3121` (not in nixpkgs), whose
  # closure needs `httpx2` (not in nixpkgs at all), `py-key-value-aio>=0.4.4`
  # (nixpkgs has 0.3.0) and `pydantic-monty==0.0.18` (nixpkgs has 0.0.17) — and
  # the pin moves with every component release. Upstream states the standalone
  # HTTP server is a complete install that replaces the component with full
  # feature parity, so we run that instead. Run only ONE ha-mcp install: do not
  # also add the component or HA's built-in `mcp_server` integration for the
  # same client.

  # One agenix env file (root:root 0400) holding:
  #   HOMEASSISTANT_TOKEN — a long-lived access token for an HA admin. HA on
  #     malina5 has `auth_providers = [ ]` (kanidm OIDC only), but long-lived
  #     tokens are independent of the auth provider: log in as a member of
  #     ha.admins, then profile → Security → Create token.
  #   MCP_SECRET_PATH — the endpoint path, e.g. /private_<token_urlsafe(16)>.
  #     In plain HTTP mode path secrecy IS the auth boundary (ha-mcp's own
  #     __main__.py says so), so it must stay out of the world-readable Nix
  #     store — hence here rather than in `environment` below. nginx proxies
  #     `/` wholesale, so it never needs to know the value either.
  age.secrets.ha-mcp-env.file = ../../../secrets/ha-mcp-env.age;

  # Server settings + OAuth client registrations. On /state, so it survives the
  # impermanence root rollback but is deliberately NOT in the ZFS-snapshot borg
  # set — everything here is cheap to recreate (the real inputs are the token and
  # secret path in the age file above, which *are* backed up as part of the repo).
  # Losing the dataset just means re-registering MCP OAuth clients.
  # The image warns and falls back to a tmpdir (losing settings on restart) if it
  # cannot write here, so the ownership below is load-bearing.
  environment.persistence."/state".directories = [
    { directory = dataDir; mode = "0700"; }
  ];

  users.users.ha-mcp = {
    inherit uid;
    group = "ha-mcp";
    isSystemUser = true;
    description = "ha-mcp container data owner";
  };
  users.groups.ha-mcp = { inherit gid; };

  # Numeric rather than by name so the rules are independent of user-creation
  # ordering. `Z` recurses: it carries the one-time 999 -> 600 migration of the
  # files the container already wrote (a `d` rule only touches the directory
  # itself, which would leave the old root-of-dir contents unwritable). Mode is
  # `-` so it re-owns without clobbering per-file modes. Harmless to keep — the
  # tree is a handful of small files.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0700 ${toString uid} ${toString gid} -"
    "Z ${dataDir} - ${toString uid} ${toString gid} -"
  ];

  # podman itself and the /var/lib/containers image store are already configured
  # by ./healthlog.nix — do not re-declare them here.

  virtualisation.oci-containers.containers.ha-mcp = {
    inherit image;
    # The image's default CMD is `ha-mcp` (stdio). `ha-mcp-web` is the
    # streamable-HTTP entrypoint.
    cmd = [ "ha-mcp-web" ];
    environmentFiles = [ config.age.secrets.ha-mcp-env.path ];
    environment = {
      HOMEASSISTANT_URL = "https://ha.${ext}";
      # 0.0.0.0 inside the container's own netns; the publish below is what
      # actually restricts reachability to beast's loopback (and thus nginx).
      MCP_HOST = "0.0.0.0";
      MCP_PORT = toString port;
    };
    volumes = [ "${dataDir}:/home/mcpuser/.ha-mcp" ];
    ports = [ "127.0.0.1:${toString port}:${toString port}" ];
    extraOptions = [
      "--add-host=ha.${ext}:${malina5Ip}"
      # Run as the dedicated host identity above instead of the image's uid 999.
      "--user=${toString uid}:${toString gid}"
    ];
  };

  # VPN-only by DNS: ha-mcp.<domain> is served only by thunder's unbound to VPN
  # clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record, and
  # beast is not publicly reachable — so no allow/deny block, same as readeck and
  # healthlog. Deliberately NO oauth2-proxy gate: MCP clients cannot complete the
  # interactive cookie flow. MCP_SECRET_PATH plus VPN-only DNS is the boundary.
  # (If that ever needs to become real auth, the image also ships `ha-mcp-oauth`
  # and `ha-mcp-oidc` entrypoints — the latter could front kanidm.)
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    # Streamable HTTP keeps a long-lived SSE stream open for server→client
    # messages. Buffering would stall it, and the default 60s read timeout would
    # tear down an idle session mid-conversation.
    extraConfig = ''
      proxy_buffering off;
      proxy_read_timeout 3600s;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
    };
  };
}
