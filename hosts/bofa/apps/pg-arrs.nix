{ config, pkgs, ... }:
let
  tracearrPasswordFile = config.sops.secrets.timescaledb-tracearr-password.path;

  apps = [
    {
      name = "sonarr";
      passwordFile = config.sops.secrets.pg-sonarr-password.path;
    }
    {
      name = "sonarr4k";
      passwordFile = config.sops.secrets.pg-sonarr4k-password.path;
    }
    {
      name = "radarr";
      passwordFile = config.sops.secrets.pg-radarr-password.path;
    }
    {
      name = "radarr4k";
      passwordFile = config.sops.secrets.pg-radarr4k-password.path;
    }
  ];

  setupScript = pkgs.writeShellScript "pg-setup-arrs" (
    ''
      export PGPASSWORD=$(cat ${tracearrPasswordFile})

      psql_exec() {
        ${pkgs.podman}/bin/podman exec -e PGPASSWORD timescaledb \
          psql -U tracearr "$@"
      }

      until ${pkgs.podman}/bin/podman exec timescaledb pg_isready -U tracearr; do
        sleep 2
      done

      setup_app() {
        local app=$1
        local pass
        pass=$(cat "$2")

        psql_exec -tc "SELECT 1 FROM pg_roles WHERE rolname='$app'" \
          | grep -q 1 \
          || psql_exec -c "CREATE USER \"$app\" WITH PASSWORD '$pass'"
        psql_exec -c "ALTER USER \"$app\" WITH PASSWORD '$pass'"

        for db in "$app-main" "$app-log"; do
          psql_exec -tc "SELECT 1 FROM pg_database WHERE datname='$db'" \
            | grep -q 1 \
            || psql_exec -c "CREATE DATABASE \"$db\" OWNER \"$app\""
          psql_exec -d "$db" -c "CREATE EXTENSION IF NOT EXISTS pg_trgm"
          psql_exec -d "$db" -c "CREATE EXTENSION IF NOT EXISTS btree_gin"
        done
      }

    ''
    + (builtins.concatStringsSep "\n" (map (a: "setup_app ${a.name} ${a.passwordFile}") apps))
  );
in
{
  sops.secrets.pg-sonarr-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.pg-sonarr4k-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.pg-radarr-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.pg-radarr4k-password = {
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
