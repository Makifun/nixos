{ baseFacts, hosts, ... }:
let
  pgbackwebPort = 8085;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      pgbackweb-bofa-outpost = {
        rule = "Host(`pgbackweb.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      pgbackweb-bofa = {
        rule = "Host(`pgbackweb.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "pgbackweb-bofa-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."pgbackweb-bofa-svc".loadBalancer.servers = [
      { url = "http://${hosts.bofa}:${toString pgbackwebPort}"; }
    ];
  };

  ligma.dnsRecords."pgbackweb.${baseFacts.domainName}".value = hosts.ligma;
}
