{ config, lib, pkgs, ... }:
let
  ext = config.homelab.ext-domain;
  domain = "git.${ext}";
  # Forgejo's HTTP port. Not 3000 — grafana already binds 127.0.0.1:3000 on beast.
  port = 3001;
  # Forgejo's built-in SSH server for git clone/push. Host sshd owns 22, so it
  # listens on 2222, opened only on the tailnet. 
  sshPort = 2222;
  clientId = "forgejo";
  # Name of the OIDC login source inside forgejo. It is also the path segment in
  # the OAuth callback (/user/oauth2/<name>/callback), so it must match the
  # originUrl registered for the `forgejo` client in modules/nixos/kanidm.nix.
  authName = "kanidm";
  exe = lib.getExe config.services.forgejo.package;
  appIni = "${config.services.forgejo.customDir}/conf/app.ini";
in
{
  # Raw OIDC client secret (bare value). The same secret is kanidm's
  # basicSecretFile on thunder (kanidm-oauth2-forgejo.age lists both host keys);
  # here it is handed to the forgejo CLI to register the kanidm login source.
  age.secrets.kanidm-oauth2-forgejo = {
    file = ../../../secrets/kanidm-oauth2-forgejo.age;
    owner = "forgejo";
    group = "forgejo";
    mode = "0400";
  };

  # stateDir holds the SQLite db, repositories, LFS objects and app.ini. It sits
  # on rpool1/safe/persist via impermanence, so it survives the root rollback
  # and is captured by the ZFS-snapshot borg backup (modules/nixos/backup.nix) —
  # no forgejo-specific dump job is needed, same convention as paperless/kanidm.
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/forgejo";
      user = "forgejo";
      group = "forgejo";
      mode = "0750";
    }
  ];

  services.forgejo = {
    enable = true;
    database.type = "sqlite3";
    lfs.enable = true;

    settings = {
      server = {
        DOMAIN = domain;
        ROOT_URL = "https://${domain}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = port;
        # Built-in SSH server on an alt port; SSH_DOMAIN is what forgejo prints
        # in the ssh:// clone URLs it shows in the UI.
        DISABLE_SSH = false;
        START_SSH_SERVER = true;
        SSH_PORT = sshPort;
        SSH_LISTEN_PORT = sshPort;
        SSH_DOMAIN = domain;
      };
      service = {
        # Login is kanidm-only: no local self-registration form, but the first
        # external (OIDC) login is allowed to auto-create the forgejo account.
        DISABLE_REGISTRATION = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
        SHOW_REGISTRATION_BUTTON = false;
        # Keep username/password + token auth on the git HTTPS endpoint so users
        # can push with personal access tokens (their OIDC login has no password).
        ENABLE_BASIC_AUTHENTICATION = true;
      };
      oauth2_client = {
        # Auto-provision the forgejo user on first kanidm login and match by the
        # short preferred_username (preferShortUsername = true in kanidm).
        ENABLE_AUTO_REGISTRATION = true;
        USERNAME = "preferred_username";
        UPDATE_AVATAR = true;
        ACCOUNT_LINKING = "auto";
      };
      # Built-in OpenID (Yadis) sign-in is a separate feature from the kanidm
      # OIDC source below; keep it off so it doesn't clutter the login page.
      openid = {
        ENABLE_OPENID_SIGNIN = false;
        ENABLE_OPENID_SIGNUP = false;
      };
    };
  };

  # git-over-SSH, reachable only over the tailnet (everything here is VPN-only).
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ sshPort ];

  # Register (or update) the kanidm OIDC login source. Forgejo stores auth
  # sources in its DB, not app.ini, so this can't be declared in `settings`; a
  # oneshot idempotently reconciles it each activation after the web service is
  # up. The secret is passed via a systemd credential, never on a long-lived
  # process's argv nor into the Nix store.
  systemd.services.forgejo-oidc = {
    description = "Register the kanidm OIDC login source in Forgejo";
    # Registration validates the client by fetching kanidm's discovery document
    # on thunder, reached over tailscale via thunder's DNS. Order after the
    # network so the first attempt isn't made before tailscale0 is up (at boot
    # this unit would otherwise fail with "lookup auth.<domain>: no such host").
    after = [ "forgejo.service" "network-online.target" "tailscaled.service" ];
    requires = [ "forgejo.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ config.services.forgejo.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = config.services.forgejo.user;
      Group = config.services.forgejo.group;
      LoadCredential = "secret:${config.age.secrets.kanidm-oauth2-forgejo.path}";
    };
    script = ''
      set -eu
      secret="$(cat "$CREDENTIALS_DIRECTORY/secret")"

      # Ordering after the network is not enough — tailscale connectivity and
      # thunder's DNS can lag a few seconds behind tailscaled starting. Poll the
      # discovery endpoint (also confirms kanidm has the client) before
      # registering, so a cold boot doesn't hard-fail the unit.
      discovery="https://auth.${ext}/oauth2/openid/${clientId}/.well-known/openid-configuration"
      for i in $(seq 1 30); do
        if ${lib.getExe pkgs.curl} -fsS -o /dev/null "$discovery"; then break; fi
        echo "waiting for kanidm discovery ($discovery): attempt $i/30"
        sleep 6
      done

      args=(
        --name ${authName}
        --provider openidConnect
        --key ${clientId}
        --secret "$secret"
        --auto-discover-url "https://auth.${ext}/oauth2/openid/${clientId}/.well-known/openid-configuration"
        --scopes openid --scopes email --scopes profile
        # Promote members of kanidm's forgejo.admins to site admin. kanidm emits
        # the value in a custom `forgejo_roles` claim (claimMaps in kanidm.nix);
        # a user without it stays a regular user.
        --group-claim-name forgejo_roles
        --admin-group forgejo-admins
      )
      # `admin auth list` prints a header then tab-separated rows: ID Name Type …
      id="$(${exe} --config ${appIni} admin auth list \
        | ${pkgs.gawk}/bin/awk -v n=${authName} '$2 == n { print $1 }')"
      if [ -n "$id" ]; then
        ${exe} --config ${appIni} admin auth update-oauth --id "$id" "''${args[@]}"
      else
        ${exe} --config ${appIni} admin auth add-oauth "''${args[@]}"
      fi
    '';
  };

  # VPN-only by DNS: git.<domain> is served only by thunder's unbound to VPN
  # clients (hosts/x86_64-linux/thunder/dns.nix); there is no public record, so
  # (like paperless) no per-vhost allow/deny block is needed.
  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    useACMEHost = config.homelab.ext-domain;
    extraConfig = ''
      client_max_body_size 512M;
    '';
    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };
}
