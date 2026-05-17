{ config, lib, pkgs, ... }:
let
  authBase = "/ligma/ligma/authentik";
  # renovate: datasource=docker depName=ghcr.io/goauthentik/server
  authTag = "2026.2.3";
  sharedEnv = {
    AUTHENTIK_POSTGRESQL__HOST = "/run/postgresql";
    AUTHENTIK_POSTGRESQL__USER = "authentik";
    AUTHENTIK_POSTGRESQL__NAME = "authentik";
    AUTHENTIK_REDIS__HOST      = "redis";
    AUTHENTIK_DISABLE_STARTUP_ANALYTICS = "true";
    AUTHENTIK_AVATARS          = "none";
  };
  sharedVolumes = [
    "${authBase}/media:/media"
    "${authBase}/custom-templates:/templates"
    "/run/postgresql:/run/postgresql"
  ];
  sharedExtraOptions = [ "--network=authentik_network" ];
in
{
  systemd.services.podman-create-authentik-network = {
    description   = "Create authentik_network podman network";
    before        = [
      "podman-authentik-redis.service"
      "podman-authentik-server.service"
      "podman-authentik-worker.service"
    ];
    requiredBy    = [
      "podman-authentik-redis.service"
      "podman-authentik-server.service"
      "podman-authentik-worker.service"
    ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path   = [ pkgs.podman ];
    script = "podman network exists authentik_network || podman network create authentik_network";
  };

  services.postgresql = {
    enable = true;
    dataDir = "${authBase}/postgresql";
    ensureDatabases = [ "authentik" ];
    ensureUsers = [{
      name = "authentik";
      ensureDBOwnership = true;
    }];
    # Trust the authentik user on Unix socket — container bind-mounts
    # /run/postgresql so peer auth won't match (different UID inside container).
    authentication = lib.mkBefore ''
      local authentik authentik trust
    '';
  };

  systemd.tmpfiles.rules = [
    "d '${authBase}'                  0755 root     root     - -"
    "d '${authBase}/postgresql'       0700 postgres postgres - -"
    "d '${authBase}/media'            0755 1000     1000     - -"
    "d '${authBase}/custom-templates' 0755 1000     1000     - -"
    "d '${authBase}/redis'            0755 999      999      - -"
  ];

  sops.secrets.authentik_env = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  virtualisation.oci-containers.containers = {
    authentik-redis = {
      image   = "docker.io/redis:7-alpine";
      volumes = [ "${authBase}/redis:/data" ];
      extraOptions = sharedExtraOptions ++ [ "--hostname=redis" ];
    };

    authentik-server = {
      image            = "ghcr.io/goauthentik/server:${authTag}";
      cmd              = [ "server" ];
      dependsOn        = [ "authentik-redis" ];
      environmentFiles = [ config.sops.secrets.authentik_env.path ];
      environment      = sharedEnv;
      ports            = [ "127.0.0.1:9000:9000" "127.0.0.1:9443:9443" ];
      volumes          = sharedVolumes;
      extraOptions     = sharedExtraOptions ++ [ "--hostname=authentik-server" ];
    };

    authentik-worker = {
      image            = "ghcr.io/goauthentik/server:${authTag}";
      cmd              = [ "worker" ];
      dependsOn        = [ "authentik-redis" ];
      environmentFiles = [ config.sops.secrets.authentik_env.path ];
      environment      = sharedEnv;
      volumes          = sharedVolumes;
      extraOptions     = sharedExtraOptions ++ [ "--hostname=authentik-worker" ];
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.authentik = {
      rule             = "Host(`auth.makifun.se`)";
      entryPoints      = [ "websecure" ];
      service          = "authentik";
      tls.certResolver = "letsencrypt";
    };
    services.authentik.loadBalancer.servers = [{ url = "http://127.0.0.1:9000"; }];
  };
}
