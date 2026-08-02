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
  sops.secrets.TORRENTING_PORT = {
    sopsFile = ../secrets.yaml;
  };

  sops.templates."qbittorrent.env" = {
    mode = "0400";
    content = ''
      TORRENTING_PORT=${config.sops.placeholder.TORRENTING_PORT}
    '';
  };

  systemd.tmpfiles.rules = [
    "d '${qbittorrentBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-qbittorrent = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      qbittorrent = {
        rule = "Host(`qbittorrent.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "qbittorrent-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      qbittorrent-outpost = {
        rule = "Host(`qbittorrent.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."qbittorrent-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:9090"; } ];
  };

  arrma.dnsRecords."qbittorrent.${baseFacts.domainName}".value = hosts.arrma;

  virtualisation.oci-containers.containers.qbittorrent = {
    # renovate: datasource=docker depName=lscr.io/linuxserver/qbittorrent
    image = "lscr.io/linuxserver/qbittorrent:5.2.3";
    environmentFiles = [ config.sops.templates."qbittorrent.env".path ];
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
}
