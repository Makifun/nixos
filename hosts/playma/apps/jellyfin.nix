{ config, pkgs, ... }:
let
  hostname = config.networking.hostName;
  jellyfinBase = "/${hostname}/${hostname}/jellyfin";
  # renovate: datasource=docker depName=docker.io/jellyfin/jellyfin
  jellyfinTag = "12.1.20260915-010956";
in
{
  systemd.tmpfiles.rules = [
    "d '${jellyfinBase}/config' 0750 1000 1000 - -"
    "d '/transcode/jellyfin'    0775 1000 1000 - -"
  ];

  # Start after rclone mounts /cloud so media is available on startup.
  systemd.services.podman-jellyfin = {
    after = [ "rclone-cloud.service" ];
    bindsTo = [ "rclone-cloud.service" ];
  };

  virtualisation.oci-containers.containers.jellyfin = {
    image = "docker.io/jellyfin/jellyfin:${jellyfinTag}";
    user = "1000:1000";
    extraOptions = [
      "--network=host"
      "--device=/dev/dri:/dev/dri"
      # /dev/dri/renderD128 is owned by the render group; the container
      # runs as 1000 and needs it for VA-API/QSV hardware transcoding.
      "--group-add=${toString config.ids.gids.render}"
      "--no-healthcheck"
    ];
    environment = {
      TZ = config.time.timeZone;
    };
    volumes = [
      "${jellyfinBase}/config:/config"
      # Cache (transcodes, image cache) is regenerable — keep it on the
      # ephemeral transcode disk.
      "/transcode/jellyfin:/cache"
      "/cloud:/cloud:ro"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    8096 # Jellyfin web UI + API
  ];
  networking.firewall.allowedUDPPorts = [
    7359 # Jellyfin client discovery
  ];
}
