{
  config,
  hosts,
  pkgs,
  ...
}:
let
  pgbackwebPort = 8085;
in
{
  sops.secrets.pgbackweb-encryption-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.pgbackweb-db-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.templates."pgbackweb.env" = {
    content = ''
      PBW_ENCRYPTION_KEY=${config.sops.placeholder.pgbackweb-encryption-key}
      PBW_POSTGRES_CONN_STRING=host=10.88.0.1 port=5432 user=pgbackweb password=${config.sops.placeholder.pgbackweb-db-password} dbname=pgbackweb sslmode=disable
      PBW_LISTEN_PORT=${toString pgbackwebPort}
      TZ=UTC
    '';
  };

  # Create the pgbackweb PostgreSQL user, grant read access for pg_dump, and
  # create the pgbackweb state database. Runs on every boot; all statements are
  # idempotent via IF NOT EXISTS / error suppression.
  systemd.services.pgbackweb-db-setup = {
    description = "Create pgbackweb user and database in TimescaleDB";
    after = [
      "podman-timescaledb.service"
      "sops-nix.service"
    ];
    requires = [ "podman-timescaledb.service" ];
    wants = [ "sops-nix.service" ];
    before = [ "podman-pgbackweb.service" ];
    wantedBy = [ "podman-pgbackweb.service" ];
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      until podman exec timescaledb psql -U tracearr -d tracearr -c "SELECT 1" >/dev/null 2>&1; do
        sleep 2
      done
      PASS=$(cat ${config.sops.secrets.pgbackweb-db-password.path})
      # Create user (ignore error if already exists).
      podman exec timescaledb psql -U tracearr -d tracearr \
        -c "CREATE USER pgbackweb WITH PASSWORD '$PASS';" 2>/dev/null || true
      # Grant SELECT on all present and future tables in all databases.
      podman exec timescaledb psql -U tracearr -d tracearr \
        -c "GRANT pg_read_all_data TO pgbackweb;" 2>/dev/null || true
      # Create the pgbackweb state database (ignore error if already exists).
      podman exec timescaledb psql -U tracearr -d tracearr \
        -c "CREATE DATABASE pgbackweb OWNER pgbackweb;" 2>/dev/null || true
    '';
  };

  systemd.services.podman-pgbackweb = {
    after = [
      "sops-nix.service"
      "pgbackweb-db-setup.service"
    ];
    wants = [ "sops-nix.service" ];
  };

  virtualisation.oci-containers.containers.pgbackweb = {
    # renovate: datasource=docker depName=eduardolat/pgbackweb
    image = "docker.io/eduardolat/pgbackweb:0.5.1";
    ports = [ "${toString pgbackwebPort}:${toString pgbackwebPort}" ];
    environmentFiles = [ config.sops.templates."pgbackweb.env".path ];
  };

  networking.firewall.extraInputRules = ''
    tcp dport ${toString pgbackwebPort} ip saddr ${hosts.ligma}/32 accept comment "pgbackweb from ligma"
  '';
}
