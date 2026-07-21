{ ... }:
let
  stormaIp = "10.10.10.12";
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
      { url = "http://${stormaIp}:${toString rclonePort}"; }
    ];
  };

  ligma.dnsRecords."rclone-storma.makifun.se".value = "10.10.10.13";
}
