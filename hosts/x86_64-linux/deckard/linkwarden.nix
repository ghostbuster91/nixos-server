{ config, pkgs, inputs, ... }:
let
  databaseName = "linkwarden";
in
{
  environment.persistence."/persist".directories = [
    {
      directory = config.services.postgresql.dataDir;
      user = "postgres";
      group = "postgres";
      mode = "0700";
    }
    {
      directory = config.services.linkwarden.storageLocation;
      user = "linkwarden";
      group = "linkwarden";
      mode = "0700";
    }
  ];

  environment.persistence."/state".directories = [
    {
      directory = config.services.linkwarden.cacheLocation;
      user = "linkwarden";
      group = "linkwarden";
      mode = "0700";
    }
  ];

  age.secrets."postgres-linkwarden-password" = {
    file = ../../../secrets/postgres-linkwarden-password.age;
    mode = "0400";
    owner = "postgres";
    group = "postgres";
  };

  age.secrets."linkwarden-postgres-password" = {
    file = ../../../secrets/postgres-linkwarden-password.age;
    mode = "0400";
    owner = "linkwarden";
    group = "linkwarden";
  };

  age.secrets."nextauth-linkwarden-secret" = {
    file = ../../../secrets/nextauth-linkwarden-secret.age;
    mode = "0400";
    owner = "linkwarden";
    group = "linkwarden";
  };

  age.secrets."linkwarden-oauth2-kanidm" = {
    file = ../../../secrets/kanidm-oauth2-linkwarden.age;
    mode = "0400";
    owner = "linkwarden";
    group = "linkwarden";
  };

  services.linkwarden = {
    enable = true;
    package = inputs.linkwardenPkgs.legacyPackages.x86_64-linux.linkwarden;
    database = {
      createLocally = false;
      # TODO use unix domain socket?
      host = "localhost";
      port = 5432;
    };
    host = "127.0.0.1";
    port = 3033;
    environment = {
      NEXT_PUBLIC_DISABLE_REGISTRATION = "true";
      NEXT_PUBLIC_AUTHENTIK_ENABLED = "true";
      AUTHENTIK_CUSTOM_NAME = "Kanidm";
      NEXTAUTH_URL = "https://linkwarden.${config.homelab.ext-domain}/api/v1/auth";
      AUTHENTIK_CLIENT_ID = "linkwarden";
      RE_ARCHIVE_LIMIT = "0";
      AUTHENTIK_ISSUER = "https://auth.${config.homelab.ext-domain}/oauth2/openid/linkwarden";
    };
    secretFiles = {
      POSTGRES_PASSWORD = config.age.secrets."linkwarden-postgres-password".path;
      NEXTAUTH_SECRET = config.age.secrets."nextauth-linkwarden-secret".path;
      AUTHENTIK_CLIENT_SECRET = config.age.secrets."linkwarden-oauth2-kanidm".path;
    };
  };

  services.nginx.virtualHosts."linkwarden.${config.homelab.ext-domain}" = {
    useACMEHost = config.homelab.ext-domain;
    forceSSL = true;

    locations."/" = {
      proxyPass = "http://127.0.0.1:${toString config.services.linkwarden.port}";
      proxyWebsockets = true;
      recommendedProxySettings = true;
    };
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    ensureDatabases = [ databaseName ];
    ensureUsers = [
      {
        name = databaseName;
        ensureDBOwnership = true;
        ensureClauses = {
          login = true;
          superuser = false;
        };
      }
    ];
  };

  systemd.services."postgresql-set-${databaseName}-password" = {
    description = "Set password for PostgreSQL role ${databaseName}";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "postgresql.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
    };

    environment.PSQL = "psql --no-psqlrc --port=${toString config.services.postgresql.settings.port}";
    path = [ pkgs.postgresql_16 pkgs.gnugrep ];

    script = ''
      set -euo pipefail
      pw=$(tr -d '\n' < ${config.age.secrets."postgres-linkwarden-password".path})
      $PSQL -c "ALTER ROLE \"${databaseName}\" WITH PASSWORD '$pw'"
    '';
  };

  environment.systemPackages = [
    pkgs.postgresql_16
  ];
}

