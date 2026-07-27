{ config, ... }:
let
  # calibre-web defaults to 8083, but that's taken by stirling-pdf (stirling.nix)
  # and 8084 is taken by loki (modules/nixos/logs/loki.nix, bound on all
  # interfaces) — calibre-web binding either fails with EADDRINUSE and the unit
  # crash-loops, so nginx proxies to a dead backend. 8085 is free on this host.
  port = 8085;
  domain = "calibre.${config.homelab.ext-domain}";
  dataDir = "/var/lib/calibre-web";
in
{
  services.calibre-web = {
    enable = true;
    listen = {
      # Bind loopback only; nginx terminates TLS and oauth2-proxy gates access.
      # Default is "::1" — use 127.0.0.1 to match the vhost proxyPass below.
      ip = "127.0.0.1";
      inherit port;
    };
    inherit dataDir;
    options = {
      # The Calibre library (metadata.db) is created/selected through the setup
      # wizard on first login, then lives under ${dataDir}/library (persisted
      # below). Left unset here because pointing calibreLibrary at a not-yet-
      # existing metadata.db would hard-fail the unit's ExecStartPre.
      enableBookUploading = true;
      enableBookConversion = true;
      enableKepubify = true;

      # Header SSO: trust the authenticated username that oauth2-proxy forwards,
      # giving each family member their own in-app account (reading progress,
      # shelves, Kobo sync) without Calibre-Web ever seeing a password. The vhost
      # gate below (modules/nixos/oauth2proxy.nix) renames kanidm's
      # preferred_username claim into the `X-User` header, so that is the header
      # to trust. This is safe only because Calibre-Web is loopback-bound and the
      # sole path to it is through oauth2-proxy — a client can't spoof X-User.
      #
      # BOOTSTRAP (one-time): Calibre-Web does NOT auto-create users, and once
      # this is enabled the password login form is bypassed. So a header naming a
      # not-yet-existing user just silently fails. On the very first deploy,
      # temporarily set `enable = false` below, log in at admin/admin123, create
      # one user per family member with the username = their kanidm short name
      # (kasper, kamil, kornel, mirek, aga, marta), promote yourself to admin,
      # then flip this back to `true` and redeploy.
      reverseProxyAuth = {
        enable = true;
        header = "X-User";
      };
    };
  };

  # dataDir holds app.db (users/settings), the book cover cache metadata and the
  # Calibre library created via the wizard. It lives on rpool1/safe/persist via
  # impermanence, so it survives the root rollback and is captured by the
  # ZFS-snapshot borg backup (modules/nixos/backup.nix) — no calibre-specific
  # backup job, same convention as paperless/mealie/kanidm.
  environment.persistence."/persist".directories = [
    {
      directory = dataDir;
      user = "calibre-web";
      group = "calibre-web";
      mode = "0700";
    }
  ];

  # VPN-only by DNS: calibre.<domain> is served only by thunder's unbound to VPN
  # clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record.
  # Access is gated by oauth2-proxy in front of nginx (already running on beast
  # for chat/comfyui/stirling), keyed on the access_calibre claim emitted by
  # kanidm's web-sentinel client for members of the web-sentinel.calibre group.
  # Calibre-Web's own weak admin login is thus never publicly reachable.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    oauth2 = {
      enable = true;
      allowedGroups = [ "access_calibre" ];
    };
    extraConfig = ''
      client_max_body_size 256M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
