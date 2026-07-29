{ config, lib, ... }:
let
  backrestPort = 9898;
in
{
  backrest.scheduleHour = 2;
  backrest.extraPaths = [ "/ligma/sugma" ];

  virtualisation.oci-containers.containers.backrest = {
    ports = lib.mkForce [ "127.0.0.1:${toString backrestPort}:9898" ];
    volumes = [
      "/ligma/ligma:/ligma/ligma:ro"
      "/ligma/sugma:/ligma/sugma:ro"
      "/ligma/restore:/ligma/restore"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      backrest-outpost = {
        rule = "Host(`backrest-ligma.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      backrest = {
        rule = "Host(`backrest-ligma.makifun.se`)";
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

  ligma.dnsRecords."backrest-ligma.makifun.se".value = "10.10.10.13";
}
