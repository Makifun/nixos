{ baseFacts, hosts, ... }:
let
  rclonePort = 6969;
  domain = "rclone-playma.${baseFacts.domainName}";
  tls = {
    certResolver = "letsencrypt";
    domains = [ { main = "*.${baseFacts.domainName}"; } ];
  };
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      rclone-playma-outpost = {
        rule = "Host(`${domain}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        inherit tls;
      };
      rclone-playma-root = {
        rule = "Host(`${domain}`) && Path(`/`)";
        priority = 20;
        entryPoints = [ "websecure" ];
        service = "rclone-playma-svc";
        middlewares = [
          "authentik"
          "rclone-playma-login-url"
        ];
        inherit tls;
      };
      rclone-playma = {
        rule = "Host(`${domain}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "rclone-playma-svc";
        middlewares = [ "authentik" ];
        inherit tls;
      };
    };
    middlewares."rclone-playma-login-url".redirectRegex = {
      regex = ".*";
      replacement = "https://${domain}/login?url=https://${domain}";
      permanent = false;
    };
    services."rclone-playma-svc".loadBalancer.servers = [
      { url = "http://${hosts.playma}:${toString rclonePort}"; }
    ];
  };

  ligma.dnsRecords."${domain}".value = hosts.ligma;
}
