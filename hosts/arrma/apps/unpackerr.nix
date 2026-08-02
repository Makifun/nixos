{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  unpackerrBase = "/${hostname}/${hostname}/unpackerr";
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers.unpackerr-metrics = {
      rule = "Host(`unpackerr-metrics.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "unpackerr-metrics-svc";
      tls.certResolver = "letsencrypt";
    };
    services."unpackerr-metrics-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:5656"; } ];
  };

  arrma.dnsRecords."unpackerr-metrics.${baseFacts.domainName}".value = hosts.arrma;

  systemd.tmpfiles.rules = [
    "d '${unpackerrBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-unpackerr = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.unpackerr = {
    # renovate: datasource=docker depName=ghcr.io/hotio/unpackerr
    image = "ghcr.io/hotio/unpackerr:release-v0.15.2";
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      UN_WEBSERVER_METRICS = "true";
    };
    extraOptions = [ "--network=container:gluetun" ];
    volumes = [
      "${unpackerrBase}:/config"
      "/slowmeme:/qbitdownloads"
    ];
  };
}
