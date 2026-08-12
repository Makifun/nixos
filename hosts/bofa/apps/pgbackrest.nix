{
  baseFacts,
  config,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  # No secrets in this file — credentials come in via env vars at runtime.
  pgbackrestConf = pkgs.writeText "pgbackrest.conf" ''
    [global]
    repo1-type=s3
    repo1-s3-endpoint=s3.${baseFacts.domainName}
    repo1-s3-bucket=pgbackrest
    repo1-s3-region=garage
    repo1-s3-uri-style=path
    repo1-retention-full=2
    repo1-retention-diff=6
    compress-type=lz4
    log-level-console=info
    log-level-file=off
    log-timestamp=n

    [${hostname}]
    pg1-path=/home/postgres/pgdata/data
    pg1-user=tracearr
    pg1-socket-path=/var/run/postgresql
  '';
  envFile = config.sops.templates."pgbackrest.env".path;
  # podman exec reads --env-file from the host; pgbackrest runs inside the container.
  exec = "${pkgs.podman}/bin/podman exec --env-file ${envFile} timescaledb pgbackrest --stanza=${hostname}";
in
{
  sops.secrets.pgbackrest-s3-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.pgbackrest-s3-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.templates."pgbackrest.env" = {
    content = ''
      PGBACKREST_REPO1_S3_KEY=${config.sops.placeholder.pgbackrest-s3-key}
      PGBACKREST_REPO1_S3_KEY_SECRET=${config.sops.placeholder.pgbackrest-s3-secret}
    '';
  };

  # Ensure sops renders the env file before the container starts.
  systemd.services.podman-timescaledb = {
    after = [ "sops-nix.service" ];
    wants = [ "sops-nix.service" ];
  };

  # Merge into the timescaledb container — lists are concatenated across modules.
  virtualisation.oci-containers.containers.timescaledb = {
    volumes = [ "${pgbackrestConf}:/etc/pgbackrest/pgbackrest.conf:ro" ];
    environmentFiles = [ envFile ];
  };

  systemd.services.pgbackrest-full = {
    description = "pgBackRest full backup";
    after = [
      "podman-timescaledb.service"
      "sops-nix.service"
    ];
    requires = [ "podman-timescaledb.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${exec} backup --type=full";
    };
  };

  systemd.timers.pgbackrest-full = {
    description = "Weekly pgBackRest full backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 01:00 UTC";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };

  systemd.services.pgbackrest-incr = {
    description = "pgBackRest incremental backup";
    after = [
      "podman-timescaledb.service"
      "sops-nix.service"
    ];
    requires = [ "podman-timescaledb.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${exec} backup --type=incr";
    };
  };

  systemd.timers.pgbackrest-incr = {
    description = "Daily pgBackRest incremental backup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon..Sat 01:00 UTC";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
  };
}
