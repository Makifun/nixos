{
  config,
  baseFacts,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  apprisePort = 8097;
  appriseBase = "/${hostname}/${hostname}/apprise";
  # renovate: datasource=docker depName=linuxserver/apprise-api registryUrl=https://lscr.io
  appriseTag = "1.5.3";
in
{
  systemd.tmpfiles.rules = [
    "d '${appriseBase}/config'      0755 root root - -"
    "d '${appriseBase}/attachments' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.apprise = {
    image = "lscr.io/linuxserver/apprise-api:${appriseTag}";
    ports = [ "127.0.0.1:${toString apprisePort}:8000" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = baseFacts.timeZone;
    };
    volumes = [
      "${appriseBase}/config:/config"
      "${appriseBase}/attachments:/attachments"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      apprise-outpost = {
        rule = "Host(`apprise.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      apprise-api = {
        rule = "Host(`apprise.${baseFacts.domainName}`) && PathPrefix(`/notify`)";
        priority = 10;
        entryPoints = [ "websecure" ];
        service = "apprise-svc";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      apprise = {
        rule = "Host(`apprise.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "apprise-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."apprise-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString apprisePort}"; }
    ];
  };

  ligma.dnsRecords."apprise.${baseFacts.domainName}".value = hosts.ligma;
}
