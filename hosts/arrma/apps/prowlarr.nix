{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  prowlarrBase = "/${hostname}/${hostname}/prowlarr";
in
{
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
    # renovate: datasource=docker depName=lscr.io/linuxserver/prowlarr
    image = "lscr.io/linuxserver/prowlarr:2.5.2";
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      PROWLARR__SERVER__PORT = "9697";
    };
    extraOptions = [ "--network=container:gluetun" ];
    volumes = [
      "${prowlarrBase}:/config"
    ];
  };

  virtualisation.oci-containers.containers.exportarr-prowlarr = {
    # renovate: datasource=docker depName=ghcr.io/onedr0p/exportarr
    image = "ghcr.io/onedr0p/exportarr:v2.3.0";
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
        tls = { };
      };
      prowlarrpg-outpost = {
        rule = "Host(`prowlarrpg.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = { };
      };
    };
    services."prowlarrpg-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:9697"; } ];
  };

  arrma.dnsRecords."prowlarrpg.${baseFacts.domainName}".value = hosts.arrma;
}
