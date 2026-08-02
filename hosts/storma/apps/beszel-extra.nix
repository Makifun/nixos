{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  systemd.tmpfiles.rules = [
    "d '/rclone-cache/.beszelrclone-cache' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/rclone-cache/.beszelrclone-cache:/extra-filesystems/rclone-cache__rclone-cache:ro"
  ];
}
