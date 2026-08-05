{
  baseFacts,
  config,
  hosts,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  infisicalPort = 8850;
  infisicalBase = "/${hostname}/${hostname}/infisical";
  # renovate: datasource=docker depName=infisical/infisical
  infisicalTag = "v0.162.16";
  # renovate: datasource=docker depName=postgres
  pgTag = "16-alpine";
  # renovate: datasource=docker depName=redis
  redisTag = "8-alpine";
in
{
  # infisical-env: |
  #   ENCRYPTION_KEY=<openssl rand -hex 16>
  #   AUTH_SECRET=<openssl rand -base64 32>
  sops.secrets.infisical-env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.services.podman-create-infisical-network = {
    description = "Create infisical_network podman network";
    before = [
      "podman-infisical-db.service"
      "podman-infisical-redis.service"
      "podman-infisical.service"
    ];
    requiredBy = [
      "podman-infisical-db.service"
      "podman-infisical-redis.service"
      "podman-infisical.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.podman ];
    script = "podman network exists infisical_network || podman network create --subnet 10.89.5.0/24 infisical_network";
  };

  systemd.tmpfiles.rules = [
    "d '${infisicalBase}'       0755 root root - -"
    "d '${infisicalBase}/db'    0700 70   70   - -"
    "d '${infisicalBase}/redis' 0755 999  999  - -"
  ];

  virtualisation.oci-containers.containers = {
    infisical-db = {
      image = "docker.io/postgres:${pgTag}";
      extraOptions = [
        "--network=infisical_network"
        "--hostname=infisical-db"
      ];
      volumes = [ "${infisicalBase}/db:/var/lib/postgresql/data" ];
      environment = {
        POSTGRES_USER = "infisical";
        POSTGRES_DB = "infisical";
        POSTGRES_HOST_AUTH_METHOD = "trust";
      };
    };

    infisical-redis = {
      image = "docker.io/redis:${redisTag}";
      extraOptions = [
        "--network=infisical_network"
        "--hostname=infisical-redis"
      ];
      volumes = [ "${infisicalBase}/redis:/data" ];
    };

    infisical = {
      image = "docker.io/infisical/infisical:${infisicalTag}";
      dependsOn = [
        "infisical-db"
        "infisical-redis"
      ];
      ports = [ "127.0.0.1:${toString infisicalPort}:8080" ];
      environment = {
        SITE_URL = "https://infisical.${baseFacts.domainName}";
        NODE_ENV = "production";
        DB_CONNECTION_URI = "postgresql://infisical@infisical-db:5432/infisical";
        REDIS_URL = "redis://infisical-redis:6379";
      };
      environmentFiles = [ config.sops.secrets.infisical-env.path ];
      extraOptions = [ "--network=infisical_network" ];
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      infisical-outpost = {
        rule = "Host(`infisical.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      infisical = {
        rule = "Host(`infisical.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "infisical-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."infisical-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString infisicalPort}"; }
    ];
  };

  ligma.dnsRecords."infisical.${baseFacts.domainName}".value = hosts.ligma;
}
