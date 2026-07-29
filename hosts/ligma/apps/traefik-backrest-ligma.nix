{ baseFacts, hosts, ... }:
let
  backrestPort = 9898;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      backrest-outpost = {
        rule = "Host(`backrest-ligma.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      backrest = {
        rule = "Host(`backrest-ligma.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "backrest-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."backrest-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString backrestPort}"; }
    ];
  };

  ligma.dnsRecords."backrest-ligma.${baseFacts.domainName}".value = hosts.ligma;
}
