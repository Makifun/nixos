{ config, pkgs, ... }:
let
  dumpDir = "/bofa/dumps";
  retentionDays = 30;
  tracearrPasswordFile = config.sops.secrets.timescaledb-tracearr-password.path;

  # All databases to dump: [ { db, user, passwordFile } ]
  databases = [
    {
      db = "tracearr";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "sonarr-main";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "sonarr-log";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "sonarr4k-main";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "sonarr4k-log";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "radarr-main";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "radarr-log";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "radarr4k-main";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
    {
      db = "radarr4k-log";
      user = "tracearr";
      passwordFile = tracearrPasswordFile;
    }
  ];

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
      OnCalendar = "03:00:00";
      RandomizedDelaySec = "15min";
      Persistent = true;
    };
  };
}
