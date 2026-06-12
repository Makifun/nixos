{
  config,
  lib,
  pkgs,
  ...
}:
let
  # renovate: datasource=docker depName=ghcr.io/mozilla-services/syncstorage-rs-postgres
  syncTag = "0.23.0";
in
{
  sops.secrets.syncstorage_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Trust syncstorage user on Unix socket for both databases.
  # Container bind-mounts /run/postgresql so peer auth won't match.
  services.postgresql.authentication = lib.mkBefore ''
    local syncstorage syncstorage trust
    local tokenserver syncstorage trust
  '';

  # Idempotent DB + user provisioning. Runs before the container starts.
  systemd.services.syncstorage-db-setup = {
    description = "Provision syncstorage PostgreSQL databases";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    before = [ "podman-syncstorage.service" ];
    requiredBy = [ "podman-syncstorage.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
    };
    path = [ config.services.postgresql.package ];
    script = ''
      psql postgres -tc "SELECT 1 FROM pg_roles WHERE rolname='syncstorage'" | grep -q 1 || \
        psql postgres -c "CREATE USER syncstorage"
      psql postgres -tc "SELECT 1 FROM pg_database WHERE datname='syncstorage'" | grep -q 1 || \
        psql postgres -c "CREATE DATABASE syncstorage OWNER syncstorage"
      psql postgres -tc "SELECT 1 FROM pg_database WHERE datname='tokenserver'" | grep -q 1 || \
        psql postgres -c "CREATE DATABASE tokenserver OWNER syncstorage"
    '';
  };

  virtualisation.oci-containers.containers.syncstorage = {
    image = "ghcr.io/mozilla-services/syncstorage-rs-postgres:${syncTag}";
    environment = {
      SYNC_HOST = "0.0.0.0";
      SYNC_PORT = "8000";
      SYNC_HUMAN_LOGS = "true";
      SYNC_TOKENSERVER__ENABLED = "true";
      SYNC_TOKENSERVER__RUN_MIGRATIONS = "true";
      SYNC_TOKENSERVER__INIT_NODE_URL = "https://firefox.makifun.se";
      SYNC_TOKENSERVER__FXA_EMAIL_DOMAIN = "api.accounts.firefox.com";
      SYNC_TOKENSERVER__FXA_OAUTH_SERVER_URL = "https://oauth.accounts.firefox.com";
      # Diesel/libpq Unix socket URL — container bind-mounts /run/postgresql
      SYNC_SYNCSTORAGE__DATABASE_URL = "postgresql:///syncstorage?host=/run/postgresql&user=syncstorage";
      SYNC_TOKENSERVER__DATABASE_URL = "postgresql:///tokenserver?host=/run/postgresql&user=syncstorage";
    };
    # syncstorage_env must contain: SYNC_MASTER_SECRET=<long-random-string>
    environmentFiles = [ config.sops.secrets.syncstorage_env.path ];
    volumes = [ "/run/postgresql:/run/postgresql" ];
    ports = [ "127.0.0.1:8000:8000" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.syncstorage = {
      rule = "Host(`firefox.makifun.se`)";
      entryPoints = [ "websecure" ];
      service = "syncstorage-svc";
      tls.certResolver = "letsencrypt";
    };
    services."syncstorage-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:8000"; } ];
  };
}
