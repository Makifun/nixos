{ pkgs, ... }:
let
  pgadminPort = 5050;

  serversJson = pkgs.writeText "pgadmin-servers.json" (
    builtins.toJSON {
      Servers = {
        "1" = {
          Name = "bofa (TimescaleDB)";
          Group = "Servers";
          Host = "10.10.10.14";
          Port = 5432;
          MaintenanceDB = "postgres";
          Username = "tracearr";
          SSLMode = "prefer";
        };
        "2" = {
          Name = "ligma (PostgreSQL)";
          Group = "Servers";
          Host = "/run/postgresql";
          Port = 5432;
          MaintenanceDB = "authentik";
          Username = "authentik";
          SSLMode = "prefer";
        };
      };
    }
  );
in
{
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/pgadmin' 0750 5050 5050 - -"
  ];

  virtualisation.oci-containers.containers.pgadmin = {
    # renovate: datasource=docker depName=dpage/pgadmin4
    image = "dpage/pgadmin4:9.16";
    environment = {
      PGADMIN_CONFIG_SERVER_MODE = "False";
      PGADMIN_DEFAULT_EMAIL = "admin@makifun.se";
      PGADMIN_DEFAULT_PASSWORD = "unused";
      # Cookie protection ties session to client IP — breaks behind Traefik.
      PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION = "False";
      PGADMIN_SERVER_JSON_FILE = "/pgadmin4/servers.json";
    };
    volumes = [
      "/ligma/ligma/pgadmin:/var/lib/pgadmin"
      "/run/postgresql:/run/postgresql"
      "${serversJson}:/pgadmin4/servers.json:ro"
    ];
    ports = [ "127.0.0.1:${toString pgadminPort}:80" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      pgadmin = {
        rule = "Host(`pgadmin.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "pgadmin-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      pgadmin-outpost = {
        rule = "Host(`pgadmin.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."pgadmin-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString pgadminPort}"; }
    ];
  };

  ligma.dnsRecords."pgadmin.makifun.se".value = "10.10.10.13";
}
