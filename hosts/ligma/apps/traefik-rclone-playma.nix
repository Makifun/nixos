{ baseFacts, hosts, ... }:
let
  rclonePort = 6969;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      rclone-playma-outpost = {
        rule = "Host(`rclone-playma.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      rclone-playma = {
        rule = "Host(`rclone-playma.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "rclone-playma-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."rclone-playma-svc".loadBalancer.servers = [
      { url = "http://${hosts.playma}:${toString rclonePort}"; }
    ];
  };

  ligma.dnsRecords."rclone-playma.${baseFacts.domainName}".value = hosts.ligma;
}
