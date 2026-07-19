{ config, pkgs, ... }:
let
  tracearrPasswordFile = config.sops.secrets.timescaledb-tracearr-password.path;
  arrsPasswordFile = config.sops.secrets.pg-arrs-password.path;

  apps = [
    "sonarr"
    "sonarr4k"
    "radarr"
    "radarr4k"
  ];

  setupScript = pkgs.writeShellScript "pg-setup-arrs" ''
    export PGPASSWORD=$(cat ${tracearrPasswordFile})

    psql_exec() {
      ${pkgs.podman}/bin/podman exec -e PGPASSWORD timescaledb \
        psql -U tracearr "$@"
    }

    until ${pkgs.podman}/bin/podman exec timescaledb pg_isready -U tracearr; do
      sleep 2
    done

    ARRS_PASS=$(cat ${arrsPasswordFile})

    setup_app() {
      local app=$1

      psql_exec -tc "SELECT 1 FROM pg_roles WHERE rolname='$app'" \
        | grep -q 1 \
        || psql_exec -c "CREATE USER \"$app\" WITH PASSWORD '$ARRS_PASS'"
      psql_exec -c "ALTER USER \"$app\" WITH PASSWORD '$ARRS_PASS'"

      for db in "$app-main" "$app-log"; do
        psql_exec -tc "SELECT 1 FROM pg_database WHERE datname='$db'" \
          | grep -q 1 \
          || psql_exec -c "CREATE DATABASE \"$db\" OWNER \"$app\""
        psql_exec -d "$db" -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
        psql_exec -d "$db" -c "CREATE EXTENSION IF NOT EXISTS btree_gin"
      done
    }

    ${builtins.concatStringsSep "\n" (map (a: "setup_app ${a}") apps)}
  '';
in
{
  sops.secrets.pg-arrs-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.services.pg-setup-arrs = {
    description = "Ensure *arr PostgreSQL users and databases on bofa";
    after = [
      "podman-timescaledb.service"
      "sops-nix.service"
    ];
    requires = [ "podman-timescaledb.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = setupScript;
    };
  };
}
