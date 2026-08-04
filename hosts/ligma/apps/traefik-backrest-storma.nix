{ baseFacts, hosts, ... }:
let
  backrestPort = 9898;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      backrest-storma-outpost = {
        rule = "Host(`backrest-storma.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      backrest-storma = {
        rule = "Host(`backrest-storma.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "backrest-storma-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."backrest-storma-svc".loadBalancer.servers = [
      { url = "http://${hosts.storma}:${toString backrestPort}"; }
    ];
  };

  ligma.dnsRecords."backrest-storma.${baseFacts.domainName}".value = hosts.ligma;
}
