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
  kumaTag = "2.5.8-slim-rootless";
  # renovate: datasource=docker depName=ghcr.io/bigboot/autokuma
  autokumaTag = "2.1.0-rc.2";

  # AutoKuma static monitors. The attribute name is the AutoKuma ID; renaming
  # it deletes the monitor and its history. parent_name is a group's ID.
  # Properties: https://autokuma.bigboot.dev/dev/entity-types/
  notify = {
    notification_name_list = [ "gotify-notification" ];
  };
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
    // notify
    // extra;

  # The app answers this code without a login.
  code = c: { accepted_statuscodes = [ c ]; };
  # No path skips the Authentik outpost, so only the outpost redirect is checked.
  outpost =
    parent: name: sub:
    http parent name "https://${sub}.${domain}/" (code "302" // { max_redirects = 0; });
  sugmaApp =
    name: sub: path: extra:
    http "sugma" name "https://${sub}.${domain}${path}" extra;

  monitors = {
    # Not "gotify": that ID is the Gotify monitor. AutoKuma fills in the token
    # at runtime (files preprocess), so it stays out of the Nix store.
    gotify-notification = {
      type = "notification";
      name = "Gotify";
      active = true;
      config = {
        type = "gotify";
        name = "Gotify";
        gotifyserverurl = "http://127.0.0.1:8096";
        gotifyapplicationToken = "{{ get_env(name='AUTOKUMA__ENV__GOTIFY_TOKEN') }}";
        gotifyPriority = 8;
      };
    };

    infra = {
      type = "group";
      name = "infra";
    };
    ligma = {
      type = "group";
      name = "ligma";
    };
    playma = {
      type = "group";
      name = "playma";
    };
    sugma = {
      type = "group";
      name = "sugma";
    };

    # infra
    opnsense = http "infra" "OPNsense" "https://${hosts.opnsense}/" { ignore_tls = true; };
    proxmox = http "infra" "Proxmox" "https://${hosts.proxmox}:8006/" { ignore_tls = true; };
    technitium = http "infra" "Technitium" "https://technitium.${domain}/" { };
    technitium-dns = {
      type = "dns";
      name = "Technitium DNS";
      parent_name = "infra";
      hostname = "auth.${domain}";
      dns_resolve_server = hosts.technitium;
      dns_resolve_type = "A";
      port = 53;
      interval = 60;
      retry_interval = 60;
      max_retries = 2;
    }
    // notify;

    # ligma
    apprise = http "ligma" "Apprise" "https://apprise.${domain}/" { };
    authentik = http "ligma" "Authentik" "https://auth.${domain}/-/health/live/" { };
    backrest-ligma = http "ligma" "Backrest (ligma)" "http://127.0.0.1:9898/" { };
    beszel = http "ligma" "Beszel" "https://beszel.${domain}/api/health" { };
    forgejo = http "ligma" "Forgejo" "https://git.${domain}/api/healthz" { };
    garage = http "ligma" "Garage S3" "https://s3.${domain}/" { accepted_statuscodes = [ "403" ]; };
    gotify = http "ligma" "Gotify" "https://gotify.${domain}/health" { };
    grafana = http "ligma" "Grafana" "https://grafana.${domain}/api/health" { };
    homepage = http "ligma" "Homepage" "https://homepage.${domain}/api/healthcheck" { };
    loki = http "ligma" "Loki" "http://127.0.0.1:3100/ready" { };
    mirror-dockerhub = http "ligma" "Mirror Docker.io" "https://dockerhub.mirror.${domain}/v2/" { };
    mirror-ghcr = http "ligma" "Mirror GHCR" "https://ghcr.mirror.${domain}/v2/" { };
    mirror-quay = http "ligma" "Mirror Quay" "https://quay.mirror.${domain}/v2/" { };
    omni = http "ligma" "Omni" "https://omni.${domain}/" { };
    openbao = http "ligma" "OpenBao" "https://openbao.${domain}/v1/sys/health" { };
    pgadmin = http "ligma" "pgAdmin" "http://127.0.0.1:5050/misc/ping" { };
    prometheus = http "ligma" "Prometheus" "http://127.0.0.1:9090/-/healthy" { };
    traefik = http "ligma" "Traefik" "http://127.0.0.1:8090/api/overview" { };
    unifi = http "ligma" "UniFi" "https://127.0.0.1:8443/status" { ignore_tls = true; };
    vaultwarden = http "ligma" "Vaultwarden" "https://vault.${domain}/alive" { };
    watchyourlan = http "ligma" "WatchYourLAN" "https://watchyourlan.${domain}/api/status/" { };

    # playma
    backrest-playma = http "playma" "Backrest (playma)" "http://${hosts.playma}:9898/" { };
    jellyfin = http "playma" "Jellyfin" "https://jellyfin.${domain}/health" { };
    plex = http "playma" "Plex" "https://${hosts.playma}:32400/identity" { ignore_tls = true; };
    rclone-playma = http "playma" "rclone (playma)" "http://${hosts.playma}:6969/" { };

    # sugma: paths that skip the Authentik outpost reach the app itself.
    autobrr = sugmaApp "autobrr" "autobrr" "/api/healthz/liveness" { };
    backrest-sugma = sugmaApp "Backrest (sugma)" "backrest-sugma" "/v1.Backrest/GetConfig" (code "405");
    bazarr = sugmaApp "Bazarr" "bazarr" "/api/system/ping" { };
    bazarr4k = sugmaApp "Bazarr 4K" "bazarr4k" "/api/system/ping" { };
    filebrowser = sugmaApp "File Browser" "filebrowser" "/static/img/logo.svg" { };
    flux = outpost "sugma" "Flux" "flux";
    gluetun = sugmaApp "Gluetun" "gluetun" "/v1/publicip/ip" { };
    havc = outpost "sugma" "HA Version Control" "havc";
    homeassistant = sugmaApp "Home Assistant" "homeassistant" "/manifest.json" { };
    hubble = outpost "sugma" "Hubble" "hubble";
    kasmcord = outpost "sugma" "Kasmcord" "kasmcord";
    mediainfo = outpost "sugma" "MediaInfo" "mediainfo";
    miniflux = sugmaApp "Miniflux" "miniflux" "/v1/version" (code "401");
    nzbget = sugmaApp "NZBGet" "nzbget" "/jsonrpc" (code "401");
    pgbackweb = outpost "sugma" "pgBackWeb" "pgbackweb";
    privatebin = sugmaApp "PrivateBin" "privatebin" "/" { };
    profilarr = sugmaApp "Profilarr" "profilarr" "/api/v1/health" { };
    prowlarr = sugmaApp "Prowlarr" "prowlarr" "/api/v1/system/status" (code "401");
    qbittorrent = sugmaApp "qBittorrent" "qbittorrent" "/api/v2/app/version" { };
    qui = sugmaApp "Qui" "qui" "/api/version" (code "403");
    radarr = sugmaApp "Radarr" "radarr" "/api/v3/system/status" (code "401");
    radarr4k = sugmaApp "Radarr 4K" "radarr4k" "/api/v3/system/status" (code "401");
    romm = sugmaApp "RomM" "romm" "/api/heartbeat" { };
    s3manager-garage = outpost "sugma" "S3 Manager (Garage)" "s3manager-garage";
    s3manager-offsite = outpost "sugma" "S3 Manager (Offsite)" "s3manager-offsite";
    seerr = sugmaApp "Seerr" "seerr" "/api/v1/status" { };
    sonarr = sugmaApp "Sonarr" "sonarr" "/api/v3/system/status" (code "401");
    sonarr4k = sugmaApp "Sonarr 4K" "sonarr4k" "/api/v3/system/status" (code "401");
    sportarr = sugmaApp "Sportarr" "sportarr" "/api/v1/system/status" (code "401");
    tracearr = sugmaApp "Tracearr" "tracearr" "/health" { };
    trawl = sugmaApp "Trawl" "trawl" "/health" { };
    unpackerr = sugmaApp "Unpackerr" "unpackerr-metrics" "/metrics" { };
    vikunja = sugmaApp "Vikunja" "vikunja" "/api/v1/info" { };
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

  sops.secrets.uptime-kuma-gotify-token = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # get_env only reads variables with the AUTOKUMA__ENV__ prefix.
  sops.templates."autokuma.env" = {
    mode = "0400";
    content = ''
      AUTOKUMA__ENV__GOTIFY_TOKEN=${config.sops.placeholder.uptime-kuma-gotify-token}
    '';
    restartUnits = [ "podman-autokuma.service" ];
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
      AUTOKUMA__FILES__PREPROCESS = "true";
      AUTOKUMA__STATIC_MONITORS = "/monitors";
      AUTOKUMA__DATA_PATH = "/data";
      AUTOKUMA__ON_DELETE = "delete";
      # The health server defaults to 8090, which Traefik uses on the host.
      AUTOKUMA__HEALTHCHECK_PORT = "";
    };
    environmentFiles = [ config.sops.templates."autokuma.env".path ];
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
