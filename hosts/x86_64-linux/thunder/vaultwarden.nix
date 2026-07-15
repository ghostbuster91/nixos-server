{ config, ... }:
let
  domain = "vault.${config.homelab.ext-domain}";
  port = 8222;
  dataDir = "/var/lib/vaultwarden";
in
{
  # ADMIN_TOKEN for the /admin panel, stored as an Argon2id PHC hash (generated
  # with `argon2 ... -id`, see docs/vaultwarden.md). The panel is only needed to
  # invite the initial administrator account; the raw token never touches the
  # Nix store. systemd reads this EnvironmentFile as root before dropping to the
  # vaultwarden user, so the default 0400 root-owned agenix secret is sufficient.
  age.secrets.vaultwarden-admin-token.file = ../../../secrets/vaultwarden-admin-token.age;

  # The vault's data directory (SQLite db, attachments, RSA keys, config.json)
  # lives on /persist so it survives the impermanence root rollback and is the
  # single source of truth. Backups are handled by modules/nixos/backup.nix,
  # which takes an *atomic* ZFS snapshot of rpool1/safe/persist before running
  # borg — a SQLite file captured from that snapshot is crash-consistent, so no
  # app-specific dump (vaultwarden's backupDir) is needed. This mirrors how every
  # other stateful service here (mattermost, mealie, actual) is backed up.
  environment.persistence."/persist".directories = [
    {
      directory = dataDir;
      mode = "0700";
      user = "vaultwarden";
      group = "vaultwarden";
    }
  ];

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";

    # Provides ADMIN_TOKEN=<argon2 phc> at runtime, kept out of the Nix store.
    environmentFile = config.age.secrets.vaultwarden-admin-token.path;

    config = {
      DOMAIN = "https://${domain}";

      # Behind the nginx reverse proxy below; listen on loopback only.
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = port;
      ROCKET_LOG = "critical";

      # Live sync ("send"/notifications) hub; nginx proxies the hub endpoints as
      # websockets below.
      ENABLE_WEBSOCKET = true;

      # Authentication is deliberately kept independent of the kanidm/OIDC stack
      # so the vault stays reachable even when the identity provider is down.
      # Accounts are local email + master-password only — no SSO is wired in.
      # Open self-registration is off; the initial admin is invited from the
      # /admin panel (INVITATIONS_ALLOWED), which works without SMTP.
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = true;
      # No SMTP configured, so skip the email-verification gate on invited users.
      SIGNUPS_VERIFY = false;

      # TOTP is built in and passkey/WebAuthn works because DOMAIN is a valid
      # HTTPS origin; both are enabled per-account from the web vault. The vault
      # master-password KDF is set to Argon2id per-account in the web vault
      # (Account Settings -> Security -> Keys). See docs/vaultwarden.md.
    };
  };

  # VPN-only: the vault.<domain> record is served only by thunder's unbound to
  # VPN clients (hosts/x86_64-linux/thunder/dns.nix), and this vhost additionally
  # refuses any request whose source is outside the VPN CIDR — so even a direct
  # hit on thunder's public IP with a spoofed Host header gets a 403.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;

    extraConfig = ''
      allow ${config.homelab.vpnCidr};
      allow 127.0.0.1;
      deny all;
    '';

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      recommendedProxySettings = true;
    };
    locations."/notifications/hub" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
    locations."/notifications/anonymous-hub" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
