{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  autobrrBase = "/${hostname}/${hostname}/autobrr";
in
{
  systemd.tmpfiles.rules = [
    "d '${autobrrBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-autobrr = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.autobrr = {
    # renovate: datasource=docker depName=ghcr.io/autobrr/autobrr
    image = "ghcr.io/autobrr/autobrr:v1.83.0";
    environment = {
      TZ = config.time.timeZone;
    };
    extraOptions = [
      "--network=container:gluetun"
      "--user=1000:1000"
    ];
    volumes = [
      "${autobrrBase}:/config"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      autobrr = {
        rule = "Host(`autobrr.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "autobrr-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      autobrr-outpost = {
        rule = "Host(`autobrr.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."autobrr-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:7474"; } ];
  };

  arrma.dnsRecords."autobrr.${baseFacts.domainName}".value = hosts.arrma;
}
