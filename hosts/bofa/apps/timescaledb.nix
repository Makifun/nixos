{
  config,
  hosts,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  pgPort = 5432;
  pgData = "/${hostname}/${hostname}/postgresql";
  # renovate: datasource=docker depName=timescale/timescaledb-ha
  timescaledbTag = "pg18.1-ts2.25.1";
  pgImage = "docker.io/timescale/timescaledb-ha:${timescaledbTag}";
in
{
  sops.secrets.timescaledb-tracearr-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Build POSTGRES_PASSWORD env file at runtime from SOPS secret.
  sops.templates."timescaledb.env" = {
    content = "POSTGRES_PASSWORD=${config.sops.placeholder.timescaledb-tracearr-password}";
  };

  systemd.tmpfiles.rules = [
    "d '${pgData}' 0750 1000 1000 - -"
  ];

  virtualisation.oci-containers.containers.timescaledb = {
    image = pgImage;
    ports = [ "${toString pgPort}:5432" ];
    volumes = [
      "${pgData}:/home/postgres/pgdata"
    ];
    environment = {
      POSTGRES_USER = "tracearr";
      POSTGRES_DB = "tracearr";
      PGDATA = "/home/postgres/pgdata/data";
    };
    environmentFiles = [ config.sops.templates."timescaledb.env".path ];
    extraOptions = [
      "--shm-size=512m"
      "--stop-timeout=60"
    ];
    # Tuned for 8 GB RAM (balloon: 5 GB min / 8 GB max), SSD. shared_buffers=25% of max.
    cmd = [
      "-c"
      "timescaledb.license=timescale"
      "-c"
      "timescaledb.max_tuples_decompressed_per_dml_transaction=0"
      "-c"
      "max_locks_per_transaction=4096"
      "-c"
      "timescaledb.telemetry_level=off"
      "-c"
      "shared_buffers=2GB"
      "-c"
      "effective_cache_size=6GB"
      "-c"
      "work_mem=5140kB"
      "-c"
      "maintenance_work_mem=512MB"
      "-c"
      "wal_buffers=16MB"
      "-c"
      "min_wal_size=1GB"
      "-c"
      "max_wal_size=4GB"
      "-c"
      "checkpoint_completion_target=0.9"
      "-c"
      "default_statistics_target=100"
      "-c"
      "random_page_cost=1.1"
      "-c"
      "effective_io_concurrency=200"
      "-c"
      "jit=off"
      "-c"
      "wal_compression=lz4"
      "-c"
      "huge_pages=try"
      "-c"
      "max_connections=200"
      "-c"
      "max_worker_processes=32"
      "-c"
      "timescaledb.max_background_workers=16"
      "-c"
      "max_parallel_workers=4"
      "-c"
      "max_parallel_workers_per_gather=2"
      "-c"
      "max_parallel_maintenance_workers=2"
      "-c"
      "wal_level=replica"
      "-c"
      "archive_mode=on"
      "-c"
      "archive_command=pgbackrest --config=/etc/pgbackrest/pgbackrest.conf --stanza=${hostname} archive-push %p"
      "-c"
      "archive_timeout=60"
    ];
  };

  # timescale/timescaledb-ha installs TimescaleDB in template1 so every database
  # created by *arr apps inherits it. Each database with the extension spawns a
  # scheduler background worker on startup, exhausting max_background_workers.
  # This service drops the extension from template1 and all non-tracearr databases
  # on every NixOS switch so the problem cannot recur.
  systemd.services.timescaledb-cleanup = {
    description = "Remove TimescaleDB from non-tracearr databases";
    after = [ "podman-timescaledb.service" ];
    requires = [ "podman-timescaledb.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      until podman exec timescaledb psql -U tracearr -c "SELECT 1" >/dev/null 2>&1; do
        sleep 2
      done
      podman exec timescaledb psql -U tracearr -d template1 \
        -c "DROP EXTENSION IF EXISTS timescaledb;"
      podman exec timescaledb psql -U tracearr -tAc \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'tracearr';" \
      | while read -r db; do
        [ -n "$db" ] && podman exec timescaledb psql -U tracearr -d "$db" \
          -c "DROP EXTENSION IF EXISTS timescaledb;" 2>/dev/null || true
      done
    '';
  };

  # Allow sugma cluster nodes to reach PostgreSQL.
  networking.firewall.extraInputRules = ''
    tcp dport ${toString pgPort} ip saddr { ${hosts.sugma01}, ${hosts.sugma02}, ${hosts.sugma03} } accept comment "TimescaleDB from sugma"
  '';
}
