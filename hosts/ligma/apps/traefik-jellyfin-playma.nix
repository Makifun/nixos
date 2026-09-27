{ baseFacts, hosts, ... }:
let
  jellyfinPort = 8096;
in
{
  # No forwardAuth: Jellyfin does its own OIDC login.
  services.traefik.dynamicConfigOptions.http = {
    routers.jellyfin = {
      rule = "Host(`jellyfin.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "jellyfin-playma-svc";
      tls = {
        certResolver = "letsencrypt";
        domains = [ { main = "*.${baseFacts.domainName}"; } ];
      };
    };
    services."jellyfin-playma-svc".loadBalancer.servers = [
      { url = "http://${hosts.playma}:${toString jellyfinPort}"; }
    ];
  };

  ligma.dnsRecords."jellyfin.${baseFacts.domainName}".value = hosts.ligma;
}
