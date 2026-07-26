{ ... }:
let
  playmaIp = "10.10.10.15";
  rclonePort = 6969;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      rclone-playma-outpost = {
        rule = "Host(`rclone-playma.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      rclone-playma = {
        rule = "Host(`rclone-playma.makifun.se`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "rclone-playma-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."rclone-playma-svc".loadBalancer.servers = [
      { url = "http://${playmaIp}:${toString rclonePort}"; }
    ];
  };

  ligma.dnsRecords."rclone-playma.makifun.se".value = playmaIp;
}
