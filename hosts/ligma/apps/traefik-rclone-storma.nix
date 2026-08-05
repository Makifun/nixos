{ baseFacts, hosts, ... }:
let
  rclonePort = 6969;
  domain = "rclone-storma.${baseFacts.domainName}";
  tls = {
    certResolver = "letsencrypt";
    domains = [ { main = "*.${baseFacts.domainName}"; } ];
  };
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      rclone-storma-outpost = {
        rule = "Host(`${domain}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        inherit tls;
      };
      # Redirect GET / → /login?url=<origin> so rclone-web auto-connects
      # to the RC API without requiring manual URL entry. Same pattern the
      # rclone launcher uses when opening the browser.
      rclone-storma-root = {
        rule = "Host(`${domain}`) && Path(`/`)";
        priority = 20;
        entryPoints = [ "websecure" ];
        service = "rclone-storma-svc";
        middlewares = [
          "authentik"
          "rclone-storma-login-url"
        ];
        inherit tls;
      };
      rclone-storma = {
        rule = "Host(`${domain}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "rclone-storma-svc";
        middlewares = [ "authentik" ];
        inherit tls;
      };
    };
    middlewares."rclone-storma-login-url".redirectRegex = {
      regex = ".*";
      replacement = "https://${domain}/login?url=https://${domain}";
      permanent = false;
    };
    services."rclone-storma-svc".loadBalancer.servers = [
      { url = "http://${hosts.storma}:${toString rclonePort}"; }
    ];
  };

  ligma.dnsRecords."${domain}".value = hosts.ligma;
}
