{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  qbittorrentBase = "/${hostname}/${hostname}/qbittorrent";
in
{
  sops.secrets.qbittorrent_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '${qbittorrentBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-qbittorrent = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.qbittorrent = {
    # renovate: datasource=docker depName=lscr.io/linuxserver/qbittorrent
    image = "lscr.io/linuxserver/qbittorrent:5.2.3";
    environmentFiles = [ config.sops.secrets.qbittorrent_env.path ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      WEBUI_PORT = "9090";
      UMASK = "002";
    };
    extraOptions = [ "--network=container:gluetun" ];
    volumes = [
      "${qbittorrentBase}:/config"
      "/slowmeme:/qbitdownloads"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      qbittorrent = {
        rule = "Host(`qbittorrent.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "qbittorrent-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      qbittorrent-outpost = {
        rule = "Host(`qbittorrent.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."qbittorrent-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:9090"; } ];
  };

  arrma.dnsRecords."qbittorrent.${baseFacts.domainName}".value = hosts.arrma;
}
