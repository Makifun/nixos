{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
in
{
  backrest.scheduleHour = 3;

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      "backrest-${hostname}" = {
        rule = "Host(`backrest-${hostname}.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "backrest-${hostname}-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      "backrest-${hostname}-outpost" = {
        rule = "Host(`backrest-${hostname}.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."backrest-${hostname}-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:9898"; } ];
  };

  arrma.dnsRecords."backrest-${hostname}.${baseFacts.domainName}".value = hosts.arrma;
}
