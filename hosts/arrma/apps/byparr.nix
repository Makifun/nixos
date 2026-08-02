{ config, ... }:
{
  systemd.services.podman-byparr = {
    after = [ "podman-gluetun.service" ];
    requires = [ "podman-gluetun.service" ];
  };

  virtualisation.oci-containers.containers.byparr = {
    # renovate: datasource=docker depName=ghcr.io/thephaseless/byparr
    image = "ghcr.io/thephaseless/byparr:main";
    environment = {
      TZ = config.time.timeZone;
      PORT = "8192";
    };
    extraOptions = [
      "--network=container:gluetun"
      "--user=1000:1000"
    ];
  };
}
