{ config, pkgs, ... }:
let
  dumpDir = "/bofa/dumps";
  pgUser = "tracearr";
  pgDb = "tracearr";
  retentionDays = 30;
  passwordFile = config.sops.secrets.timescaledb-tracearr-password.path;
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
    script = ''
      stamp=$(date -u +%Y%m%d_%H%M%S)
      out="${dumpDir}/${pgDb}_$stamp.dump"
      tmp="${dumpDir}/${pgDb}_$stamp.tmp"
      cleanup() { rm -f "$tmp"; }
      trap cleanup EXIT

      export PGPASSWORD=$(cat ${passwordFile})
      ${pkgs.podman}/bin/podman exec -e PGPASSWORD timescaledb \
        pg_dump -U ${pgUser} -Fc ${pgDb} > "$tmp"
      mv "$tmp" "$out"
      echo "dump: $out ($(du -sh "$out" | cut -f1))"

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
