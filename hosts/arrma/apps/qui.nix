{ config, ... }:
let
  hostname = config.networking.hostName;
  configBase = "/${hostname}/${hostname}/qui";
in
{
  systemd.tmpfiles.rules = [
    "d '${configBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-qui = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.qui = {
    # renovate: datasource=docker depName=ghcr.io/autobrr/qui
    image = "ghcr.io/autobrr/qui:v1.24.0";
    environment = {
      TZ = config.time.timeZone;
    };
    extraOptions = [
      "--network=container:gluetun"
      "--user=1000:1000"
    ];
    volumes = [
      "${configBase}:/config"
      "/slowmeme:/qbitdownloads"
    ];
  };
}
