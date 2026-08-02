{ config, ... }:
let
  hostname = config.networking.hostName;
  configBase = "/${hostname}/${hostname}/autobrr";
in
{
  systemd.tmpfiles.rules = [
    "d '${configBase}' 0750 1000 1000 - -"
  ];

  systemd.services.podman-autobrr = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.autobrr = {
    # renovate: datasource=docker depName=ghcr.io/autobrr/autobrr
    image = "ghcr.io/autobrr/autobrr:v1.83.0";
    environment = {
      TZ = config.time.timeZone;
    };
    extraOptions = [
      "--network=container:gluetun"
      "--user=1000:1000"
    ];
    volumes = [
      "${configBase}:/config"
    ];
  };
}
