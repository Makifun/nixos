{ config, ... }:
let
  plexBase = "/playma/playma/plex";
  # renovate: datasource=docker depName=lscr.io/linuxserver/plex
  plexTag = "1.41.3.9314-a0bfb8370-ls244";
in
{
  # PLEX_CLAIM token links the server to a Plex account on first boot.
  # Expires after 5 minutes — only needed once. Get from plex.tv/claim.
  sops.secrets.plex-claim = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.templates."plex.env" = {
    content = "PLEX_CLAIM=${config.sops.placeholder.plex-claim}\n";
  };

  systemd.tmpfiles.rules = [
    "d '${plexBase}/config' 0750 root root - -"
  ];

  # Start after rclone mounts /cloud so media is available on startup.
  systemd.services.podman-plex = {
    after = [ "rclone-cloud.service" ];
    wants = [ "rclone-cloud.service" ];
  };

  virtualisation.oci-containers.containers.plex = {
    image = "lscr.io/linuxserver/plex:${plexTag}";
    extraOptions = [ "--network=host" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "Europe/Stockholm";
      VERSION = "docker";
    };
    environmentFiles = [ config.sops.templates."plex.env".path ];
    volumes = [
      "${plexBase}/config:/config"
      "/cloud:/cloud:ro"
      "/transcode:/transcode"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    32400 # Plex web UI + API
    32469 # Plex DLNA
  ];
  networking.firewall.allowedUDPPorts = [
    32410
    32412
    32413
    32414 # GDM network discovery
  ];
}
