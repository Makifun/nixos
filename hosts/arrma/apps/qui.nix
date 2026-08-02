{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  quiBase = "/${hostname}/${hostname}/qui";
in
{
  systemd.tmpfiles.rules = [
    "d '${quiBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-qui = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.qui = {
    # renovate: datasource=docker depName=ghcr.io/autobrr/qui
    image = "ghcr.io/autobrr/qui:v1.24.0";
    environment = {
      TZ = config.time.timeZone;
    };
    extraOptions = [
      "--network=container:gluetun"
      "--user=1000:1000"
    ];
    volumes = [
      "${quiBase}:/config"
      "/slowmeme:/qbitdownloads"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      qui = {
        rule = "Host(`qui.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "qui-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      qui-outpost = {
        rule = "Host(`qui.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."qui-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:7476"; } ];
  };

  arrma.dnsRecords."qui.${baseFacts.domainName}".value = hosts.arrma;
}
