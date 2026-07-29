{ config, pkgs, ... }:
let
  hostname = config.networking.hostName;
  plexBase = "/${hostname}/${hostname}/plex";
  # renovate: datasource=docker depName=lscr.io/linuxserver/plex
  plexTag = "1.43.3";
in
{
  systemd.tmpfiles.rules = [
    "d '${plexBase}/config'   0750 root root - -"
    "d '/transcode/plex'      0775 1000 1000 - -"
  ];

  # Start after rclone mounts /cloud so media is available on startup.
  systemd.services.podman-plex = {
    after = [ "rclone-cloud.service" ];
    bindsTo = [ "rclone-cloud.service" ];
    serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
  };

  virtualisation.oci-containers.containers.plex = {
    image = "lscr.io/linuxserver/plex:${plexTag}";
    extraOptions = [
      "--network=host"
      "--device=/dev/dri:/dev/dri"
      "--no-healthcheck"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "Europe/Stockholm";
      VERSION = "docker";
    };
    volumes = [
      "${plexBase}/config:/config"
      "/cloud/Serie:/tv:ro"
      "/cloud/Serie4k:/tv4k:ro"
      "/cloud/Anime:/anime:ro"
      "/cloud/Film:/movies:ro"
      "/cloud/Film4k:/movies4k:ro"
      "/cloud/Asian:/asian:ro"
      "/cloud/FilmSWE:/moviesswe:ro"
      "/transcode/plex:/transcode"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    32400 # Plex web UI + API
  ];
  networking.firewall.allowedUDPPorts = [
    32410
    32412
    32413
    32414 # GDM network discovery
  ];
}
