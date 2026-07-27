{ hosts, ... }:
let
  rclonePort = 6969;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      rclone-storma-outpost = {
        rule = "Host(`rclone-storma.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      rclone-storma = {
        rule = "Host(`rclone-storma.makifun.se`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "rclone-storma-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."rclone-storma-svc".loadBalancer.servers = [
      { url = "http://${hosts.storma}:${toString rclonePort}"; }
    ];
  };

  ligma.dnsRecords."rclone-storma.makifun.se".value = hosts.ligma;
}
