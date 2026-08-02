{ config, ... }:
let
  hostname = config.networking.hostName;
  configBase = "/${hostname}/${hostname}/qbittorrent";
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
    "d '${configBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-qbittorrent = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

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
      "${configBase}:/config"
      "/slowmeme:/qbitdownloads"
    ];
  };
}
