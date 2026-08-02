{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  systemd.tmpfiles.rules = [
    "d '/transcode/.beszeltranscode'       0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/transcode/.beszeltranscode:/extra-filesystems/transcode__transcode:ro"
  ];
}
