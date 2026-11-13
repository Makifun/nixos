{ baseFacts, hosts, ... }:
let
  rclonePlaymaPort = 6969;
  rcloneGuiPort = 6971;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      rclone-gui-outpost = {
        rule = "Host(`rclone-gui.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      rclone-gui = {
        rule = "Host(`rclone-gui.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "rclone-gui-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
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
    services."rclone-gui-svc".loadBalancer.servers = [
      { url = "http://${hosts.playma}:${toString rcloneGuiPort}"; }
    ];
    services."rclone-playma-svc".loadBalancer.servers = [
      { url = "http://${hosts.playma}:${toString rclonePlaymaPort}"; }
    ];
  };

  ligma.dnsRecords."rclone-playma.${baseFacts.domainName}".value = hosts.ligma;
}
