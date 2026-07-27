{ hosts, ... }:
let
  playmaIp = hosts.playma;
  backrestPort = 9898;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      backrest-playma-outpost = {
        rule = "Host(`backrest-playma.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      backrest-playma = {
        rule = "Host(`backrest-playma.makifun.se`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "backrest-playma-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."backrest-playma-svc".loadBalancer.servers = [
      { url = "http://${playmaIp}:${toString backrestPort}"; }
    ];
  };

  ligma.dnsRecords."backrest-playma.makifun.se".value = hosts.ligma;
}
