{ config, pkgs, ... }:
let
  pgPort = 5432;
  pgData = "/bofa/bofa/postgresql";
  # renovate: datasource=docker depName=timescale/timescaledb-ha
  pgImage = "timescale/timescaledb-ha:pg18.1-ts2.25.0";
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
    # max_worker_processes=32: pgtune says 4 (CPU count) but TimescaleDB needs
    # timescaledb.max_background_workers + max_parallel_workers + autovacuum(3) ≥ 23.
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
      "io_method=io_uring"
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
    ];
  };

  # Allow sugma cluster nodes to reach PostgreSQL.
  networking.firewall.extraInputRules = ''
    tcp dport ${toString pgPort} ip saddr { 10.10.10.26/32, 10.10.10.27/32, 10.10.10.28/32 } accept comment "TimescaleDB from sugma"
  '';
}
