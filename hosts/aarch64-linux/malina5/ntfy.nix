{ config, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "ntfy.${ext}";
  port = 2586;
in
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      # Public origin. Required for attachment download URLs and for iOS push on
      # a self-hosted server; ntfy also uses it to build topic links.
      base-url = "https://${domain}";
      # Bind loopback only; nginx terminates TLS and is the sole ingress.
      listen-http = "127.0.0.1:${toString port}";
      # nginx sets X-Forwarded-For; trust it so rate-limiting keys on the real
      # client IP rather than 127.0.0.1.
      behind-proxy = true;
      # VPN-only service (see the DNS note below), so leave access open —
      # anyone on the tailnet can publish/subscribe. There is deliberately no
      # oauth2-proxy gate: ntfy's mobile apps and publish scripts hit the API
      # directly and can't perform the interactive OIDC browser flow. To lock
      # it down later, set auth-default-access = "deny-all" and provision users
      # with the `ntfy` CLI (auth-file lives under the persisted state dir).
    };
  };

  # cache-file.db (message cache), attachments and user.db (auth) live under the
  # module's StateDirectory. It runs under DynamicUser, so systemd materialises
  # that at /var/lib/private/ntfy-sh (and symlinks /var/lib/ntfy-sh -> it);
  # persist that real path — the same DynamicUser convention as mealie, esphome,
  # open-webui and atticd. systemd re-chowns it to the dynamic UID on start, so
  # no user/group is set here. On rpool1/safe/persist it survives the root
  # rollback and folds into the ZFS-snapshot borg backup (backup.nix) — no
  # ntfy-specific job.
  environment.persistence."/persist".directories = [
    { directory = "/var/lib/private/ntfy-sh"; mode = "0700"; }
  ];

  # VPN-only by DNS: ntfy.<domain> is served only by thunder's unbound to VPN
  # clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record, so
  # no allow/deny block is needed (malina5 is not publicly reachable).
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    extraConfig = ''
      # Attachments (matches ntfy's default attachment-file-size-limit).
      client_max_body_size 15M;
      # ntfy subscriptions are long-lived SSE/WebSocket streams: don't buffer
      # them and keep them open well past nginx's 60s default.
      proxy_buffering off;
      proxy_request_buffering off;
      proxy_read_timeout 3m;
      proxy_send_timeout 3m;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
