{
  baseFacts,
  config,
  hosts,
  lib,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  domain = baseFacts.domainName;
  kumaPort = 3001;
  kumaBase = "/${hostname}/${hostname}/uptime-kuma";
  autokumaBase = "/${hostname}/${hostname}/autokuma";
  # renovate: datasource=docker depName=louislam/uptime-kuma
  kumaTag = "2.5.7-slim-rootless";
  # renovate: datasource=docker depName=ghcr.io/bigboot/autokuma
  autokumaTag = "2.1.0-rc.2";

  # AutoKuma static monitors. The attribute name is the AutoKuma ID; renaming
  # it deletes the monitor and its history. parent_name is a group's ID.
  # Properties: https://autokuma.bigboot.dev/dev/entity-types/
  http =
    parent: name: url: extra:
    {
      type = "http";
      inherit name url;
      parent_name = parent;
      interval = 60;
      retry_interval = 60;
      max_retries = 2;
    }
    // extra;

  monitors = {
    infra = {
      type = "group";
      name = "Infrastructure";
    };
    apps = {
      type = "group";
      name = "Apps";
    };
    media = {
      type = "group";
      name = "Media";
    };

    authentik = http "infra" "Authentik" "https://auth.${domain}/-/health/live/" { };
    openbao = http "infra" "OpenBao" "https://openbao.${domain}/v1/sys/health" { };
    omni = http "infra" "Omni" "https://omni.${domain}/" { };
    technitium = http "infra" "Technitium" "https://technitium.${domain}/" { };
    garage = http "infra" "Garage S3" "https://s3.${domain}/" {
      # Anonymous S3 requests get AccessDenied.
      accepted_statuscodes = [ "403" ];
    };

    forgejo = http "apps" "Forgejo" "https://git.${domain}/api/healthz" { };
    vaultwarden = http "apps" "Vaultwarden" "https://vault.${domain}/alive" { };
    gotify = http "apps" "Gotify" "https://gotify.${domain}/health" { };
    grafana = http "apps" "Grafana" "https://grafana.${domain}/api/health" { };
    beszel = http "apps" "Beszel" "https://beszel.${domain}/api/health" { };

    jellyfin = http "media" "Jellyfin" "https://jellyfin.${domain}/health" { };
  };

  monitorsDir = pkgs.runCommand "autokuma-monitors" { } (
    ''
      mkdir $out
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (id: m: ''
        cp ${pkgs.writeText "${id}.json" (builtins.toJSON m)} $out/${id}.json
      '') monitors
    )
  );

  # Paths the public status page needs. Everything else (dashboard, socket.io,
  # settings) goes through Authentik.
  publicPaths = [
    "/"
    "/api/entry-page"
    "/setup-database-info"
    "/robots.txt"
    "/manifest.json"
    "/serviceWorker.js"
    "/favicon.ico"
    "/apple-touch-icon.png"
    "/icon.svg"
    "/icon.png"
    "/icon-192x192.png"
    "/icon-512x512.png"
  ];
  publicPrefixes = [
    "/status/"
    "/api/status-page/"
    "/api/badge/"
    "/assets/"
    "/upload/"
  ];
  publicRule = lib.concatStringsSep " || " (
    map (p: "Path(`${p}`)") publicPaths ++ map (p: "PathPrefix(`${p}`)") publicPrefixes
  );

  tls = {
    certResolver = "letsencrypt";
    domains = [ { main = "*.${domain}"; } ];
  };
in
{
  # Password of the Uptime Kuma "admin" user, for AutoKuma.
  sops.secrets.uptime-kuma-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # The rootless image runs as node (UID 1000).
  systemd.tmpfiles.rules = [
    "d '${kumaBase}' 0700 1000 1000 - -"
    "d '${autokumaBase}' 0700 root root - -"
  ];

  virtualisation.oci-containers.containers.uptime-kuma = {
    image = "docker.io/louislam/uptime-kuma:${kumaTag}";
    environment = {
      TZ = baseFacts.timeZone;
      UPTIME_KUMA_HOST = "127.0.0.1";
      UPTIME_KUMA_PORT = toString kumaPort;
      UPTIME_KUMA_DB_TYPE = "sqlite";
    };
    volumes = [ "${kumaBase}:/app/data" ];
    # Host network so monitors can also reach loopback-only services.
    extraOptions = [ "--network=host" ];
  };

  virtualisation.oci-containers.containers.autokuma = {
    image = "ghcr.io/bigboot/autokuma:${autokumaTag}";
    dependsOn = [ "uptime-kuma" ];
    environment = {
      AUTOKUMA__KUMA__URL = "http://127.0.0.1:${toString kumaPort}";
      AUTOKUMA__KUMA__USERNAME = "admin";
      AUTOKUMA__KUMA__PASSWORD = "@/run/secrets/kuma-password";
      AUTOKUMA__DOCKER__ENABLED = "false";
      AUTOKUMA__FILES__ENABLED = "true";
      AUTOKUMA__STATIC_MONITORS = "/monitors";
      AUTOKUMA__DATA_PATH = "/data";
      AUTOKUMA__ON_DELETE = "delete";
      # The health server defaults to 8090, which Traefik uses on the host.
      AUTOKUMA__HEALTHCHECK_PORT = "";
    };
    volumes = [
      "${monitorsDir}:/monitors:ro"
      "${autokumaBase}:/data"
      "${config.sops.secrets.uptime-kuma-password.path}:/run/secrets/kuma-password:ro"
    ];
    extraOptions = [
      "--network=host"
      "--no-healthcheck"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      uptime-kuma-public = {
        rule = "Host(`status.${domain}`) && (${publicRule})";
        priority = 20;
        entryPoints = [ "websecure" ];
        service = "uptime-kuma";
        inherit tls;
      };
      uptime-kuma-outpost = {
        rule = "Host(`status.${domain}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        inherit tls;
      };
      uptime-kuma = {
        rule = "Host(`status.${domain}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "uptime-kuma";
        middlewares = [ "authentik" ];
        inherit tls;
      };
    };
    services.uptime-kuma.loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString kumaPort}"; }
    ];
  };

  ligma.dnsRecords."status.${domain}".value = hosts.ligma;
}
