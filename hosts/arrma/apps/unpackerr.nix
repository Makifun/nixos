{ config, ... }:
let
  hostname = config.networking.hostName;
  configBase = "/${hostname}/${hostname}/unpackerr";
in
{
  systemd.tmpfiles.rules = [
    "d '${configBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-unpackerr = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.unpackerr = {
    # renovate: datasource=docker depName=ghcr.io/hotio/unpackerr
    image = "ghcr.io/hotio/unpackerr:release-v0.15.2";
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      UN_WEBSERVER_METRICS = "true";
    };
    extraOptions = [ "--network=container:gluetun" ];
    volumes = [
      "${configBase}:/config"
      "/slowmeme:/qbitdownloads"
    ];
  };
}
