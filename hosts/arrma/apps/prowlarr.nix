{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  prowlarrBase = "/${hostname}/${hostname}/prowlarr";
  # renovate: datasource=docker depName=lscr.io/linuxserver/prowlarr
  prowlarrTag = "2.5.2";
  # renovate: datasource=docker depName=ghcr.io/onedr0p/exportarr
  exportarrTag = "v2.3.0";
in
{
  # prowlarr_env: |
  #   PROWLARR__POSTGRES__PASSWORD=<password>
  sops.secrets.prowlarr_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '${prowlarrBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-prowlarr = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  # exportarr reads prowlarr's config.xml for the API key; start after prowlarr.
  systemd.services.podman-exportarr-prowlarr = {
    after = [ "podman-prowlarr.service" ];
    requires = [ "podman-prowlarr.service" ];
  };

  virtualisation.oci-containers.containers.prowlarr = {
    image = "lscr.io/linuxserver/prowlarr:${prowlarrTag}";
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      PROWLARR__SERVER__PORT = "9697";
      PROWLARR__POSTGRES__HOST = hosts.bofa;
      PROWLARR__POSTGRES__PORT = "5432";
      PROWLARR__POSTGRES__USER = "prowlarrpg";
      PROWLARR__POSTGRES__MAINDB = "prowlarrpg-main";
      PROWLARR__POSTGRES__LOGDB = "prowlarrpg-log";
    };
    environmentFiles = [ config.sops.secrets.prowlarr_env.path ];
    extraOptions = [ "--network=container:gluetun" ];
    volumes = [
      "${prowlarrBase}:/config"
    ];
  };

  virtualisation.oci-containers.containers.exportarr-prowlarr = {
    image = "ghcr.io/onedr0p/exportarr:${exportarrTag}";
    cmd = [ "prowlarr" ];
    environment = {
      PORT = "9707";
      URL = "http://localhost:9697";
      CONFIG = "/config/config.xml";
    };
    extraOptions = [
      "--network=container:gluetun"
      "--user=1000:1000"
    ];
    volumes = [
      "${prowlarrBase}:/config:ro"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      prowlarrpg = {
        rule = "Host(`prowlarrpg.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "prowlarrpg-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      prowlarrpg-outpost = {
        rule = "Host(`prowlarrpg.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."prowlarrpg-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:9697"; } ];
  };

  arrma.dnsRecords."prowlarrpg.${baseFacts.domainName}".value = hosts.arrma;
}
