{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  nzbgetBase = "/${hostname}/${hostname}/nzbget";
in
{
  systemd.tmpfiles.rules = [
    "d '${nzbgetBase}' 0750 1000 1000 - -"
  ];

  virtualisation.oci-containers.containers.nzbget = {
    # renovate: datasource=docker depName=lscr.io/linuxserver/nzbget
    image = "lscr.io/linuxserver/nzbget:version-v26.2";
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
    };
    volumes = [
      "${nzbgetBase}:/config"
      "/nicememe:/nzbgetdownloads"
    ];
    ports = [
      "6789:6789"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      nzbget = {
        rule = "Host(`nzbget.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "nzbget-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      nzbget-outpost = {
        rule = "Host(`nzbget.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."nzbget-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:6789"; } ];
  };

  arrma.dnsRecords."nzbget.${baseFacts.domainName}".value = hosts.arrma;
}
