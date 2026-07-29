{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  backrest.scheduleHour = 3;
  backrest.extraPaths = [ "/bofa/dumps" ];

  virtualisation.oci-containers.containers.backrest.volumes = [
    "/${hostname}/${hostname}:/${hostname}/${hostname}:ro"
    "/bofa/dumps:/bofa/dumps:ro"
    "/${hostname}/restore:/${hostname}/restore"
  ];
}
