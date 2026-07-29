{ config, pkgs, ... }:
let
  hostname = config.networking.hostName;
  dumpDir = "/${hostname}/${hostname}/dumps";
  retentionDays = 30;
  tracearrPasswordFile = config.sops.secrets.timescaledb-tracearr-password.path;
  arrsPasswordFile = config.sops.secrets.pg-arrs-password.path;

  arrsApps = [
    "sonarrpg"
    "sonarr4kpg"
    "radarrpg"
    "radarr4kpg"
    "prowlarrpg"
  ];

  bazarrApps = [
    "bazarr"
    "bazarr4k"
  ];

  # All databases to dump: [ { db, user, passwordFile } ]
  databases = [
    {
      db = "tracearr";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
  ]
  ++ builtins.concatMap (app: [
    {
      db = "${app}-main";
      user = app;
      passwordFile = arrsPasswordFile;
    }
    {
      db = "${app}-log";
      user = app;
      passwordFile = arrsPasswordFile;
    }
  ]) arrsApps
  ++ map (app: {
    db = app;
    user = app;
    passwordFile = arrsPasswordFile;
  }) bazarrApps;

  dumpOneDb =
    {
      db,
      user,
      passwordFile,
    }:
    ''
      export PGPASSWORD=$(cat ${passwordFile})
      if ${pkgs.podman}/bin/podman exec -e PGPASSWORD timescaledb \
          psql -U ${user} -tc "SELECT 1 FROM pg_database WHERE datname='${db}'" \
          | grep -q 1; then
        stamp=$(date -u +%Y%m%d_%H%M%S)
        out="${dumpDir}/${db}_$stamp.dump"
        tmp="${dumpDir}/${db}_$stamp.tmp"
        cleanup() { rm -f "$tmp"; }
        trap cleanup EXIT
        ${pkgs.podman}/bin/podman exec -e PGPASSWORD timescaledb \
          pg_dump -U ${user} -Fc ${db} > "$tmp"
        mv "$tmp" "$out"
        echo "dump: $out ($(du -sh "$out" | cut -f1))"
      else
        echo "skip: ${db} does not exist yet"
      fi
    '';
in
{
  systemd.tmpfiles.rules = [
    "d '${dumpDir}' 0750 root root - -"
  ];

  systemd.services.pg-dump-bofa = {
    description = "PostgreSQL logical dump — bofa databases";
    after = [
      "podman-timescaledb.service"
      "sops-nix.service"
    ];
    requires = [ "podman-timescaledb.service" ];
    serviceConfig.Type = "oneshot";
    script = (builtins.concatStringsSep "\n" (map dumpOneDb databases)) + ''
      # Prune dumps older than ${toString retentionDays} days
      find ${dumpDir} -name '*.dump' -mtime +${toString retentionDays} -delete
    '';
  };

  systemd.timers.pg-dump-bofa = {
    description = "Daily PostgreSQL dump timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:00:00";
      RandomizedDelaySec = "15min";
      Persistent = true;
    };
  };
}
