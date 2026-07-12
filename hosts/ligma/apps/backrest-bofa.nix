{ ... }:
let
  bofaIp = "10.10.10.14";
  backrestPort = 9898;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      backrest-bofa-outpost = {
        rule = "Host(`backrest-bofa.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      backrest-bofa = {
        rule = "Host(`backrest-bofa.makifun.se`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "backrest-bofa-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."backrest-bofa-svc".loadBalancer.servers = [
      { url = "http://${bofaIp}:${toString backrestPort}"; }
    ];
  };

  ligma.dnsRecords."backrest-bofa.makifun.se".value = "10.10.10.13";
}
