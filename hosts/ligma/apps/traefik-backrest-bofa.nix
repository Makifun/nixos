{ baseFacts, hosts, ... }:
let
  backrestPort = 9898;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      backrest-bofa-outpost = {
        rule = "Host(`backrest-bofa.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      backrest-bofa = {
        rule = "Host(`backrest-bofa.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "backrest-bofa-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."backrest-bofa-svc".loadBalancer.servers = [
      { url = "http://${hosts.bofa}:${toString backrestPort}"; }
    ];
  };

  ligma.dnsRecords."backrest-bofa.${baseFacts.domainName}".value = hosts.ligma;
}
