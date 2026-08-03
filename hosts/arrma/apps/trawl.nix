{
  baseFacts,
  config,
  hosts,
  ...
}:
{
  systemd.services.podman-trawl = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.trawl = {
    # renovate: datasource=docker depName=ghcr.io/germondai/trawl
    image = "ghcr.io/germondai/trawl:1.3.1";
    environment = {
      TZ = config.time.timeZone;
      PORT = "8191";
    };
    extraOptions = [
      "--network=container:gluetun"
      "--shm-size=1g"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      trawl = {
        rule = "Host(`trawl.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "trawl-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      trawl-outpost = {
        rule = "Host(`trawl.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."trawl-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:8191"; } ];
  };

  arrma.dnsRecords."trawl.${baseFacts.domainName}".value = hosts.arrma;
}
