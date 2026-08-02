{ config, ... }:
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
}
