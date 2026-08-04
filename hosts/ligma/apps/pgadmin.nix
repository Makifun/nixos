{
  baseFacts,
  config,
  hosts,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  pgadminPort = 5050;
  # renovate: datasource=docker depName=dpage/pgadmin4
  pgadminTag = "9.17";

  serversJson = pkgs.writeText "pgadmin-servers.json" (
    builtins.toJSON {
      Servers = {
        "1" = {
          Name = "bofa (TimescaleDB)";
          Group = "Servers";
          Host = hosts.bofa;
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
    "d '/${hostname}/${hostname}/pgadmin' 0750 5050 5050 - -"
  ];

  virtualisation.oci-containers.containers.pgadmin = {
    image = "dpage/pgadmin4:${pgadminTag}";
    environment = {
      PGADMIN_CONFIG_SERVER_MODE = "False";
      PGADMIN_DEFAULT_EMAIL = "admin@${baseFacts.domainName}";
      PGADMIN_DEFAULT_PASSWORD = "unused";
      # Cookie protection ties session to client IP — breaks behind Traefik.
      PGADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION = "False";
      PGADMIN_SERVER_JSON_FILE = "/pgadmin4/servers.json";
    };
    volumes = [
      "/${hostname}/${hostname}/pgadmin:/var/lib/pgadmin"
      "/run/postgresql:/run/postgresql"
      "${serversJson}:/pgadmin4/servers.json:ro"
    ];
    ports = [ "127.0.0.1:${toString pgadminPort}:80" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      pgadmin = {
        rule = "Host(`pgadmin.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "pgadmin-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      pgadmin-outpost = {
        rule = "Host(`pgadmin.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."pgadmin-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString pgadminPort}"; }
    ];
  };

  ligma.dnsRecords."pgadmin.${baseFacts.domainName}".value = hosts.ligma;
}
