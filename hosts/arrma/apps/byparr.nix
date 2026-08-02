{
  baseFacts,
  config,
  hosts,
  ...
}:
{
  systemd.services.podman-byparr = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.byparr = {
    # renovate: datasource=docker depName=ghcr.io/thephaseless/byparr
    image = "ghcr.io/thephaseless/byparr:main";
    environment = {
      TZ = config.time.timeZone;
      PORT = "8192";
    };
    extraOptions = [
      "--network=container:gluetun"
      "--user=1000:1000"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      byparr = {
        rule = "Host(`byparr.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "byparr-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      byparr-outpost = {
        rule = "Host(`byparr.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."byparr-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:8192"; } ];
  };

  arrma.dnsRecords."byparr.${baseFacts.domainName}".value = hosts.arrma;
}
