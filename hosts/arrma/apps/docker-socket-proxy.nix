{
  baseFacts,
  hosts,
  ...
}:
{
  virtualisation.oci-containers.containers.docker-socket-proxy = {
    # renovate: datasource=docker depName=ghcr.io/tecnativa/docker-socket-proxy
    image = "ghcr.io/tecnativa/docker-socket-proxy:0.3.0";
    environment = {
      CONTAINERS = "1";
      INFO = "1";
      VERSION = "1";
      STATS = "1";
    };
    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock:ro"
    ];
    ports = [ "127.0.0.1:2375:2375" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers."docker-arrma" = {
      rule = "Host(`docker-arrma.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "docker-arrma-svc";
      middlewares = [ "ligma-only" ];
      tls = {
        certResolver = "letsencrypt";
        domains = [ { main = "*.${baseFacts.domainName}"; } ];
      };
    };
    middlewares."ligma-only".ipAllowList.sourceRange = [ "${hosts.ligma}/32" ];
    services."docker-arrma-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:2375"; } ];
  };

  arrma.dnsRecords."docker-arrma.${baseFacts.domainName}".value = hosts.arrma;
}
