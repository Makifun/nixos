{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  backrest.scheduleHour = 3;
  backrest.extraPaths = [ "/${hostname}/dumps" ];

  virtualisation.oci-containers.containers.backrest.volumes = [
    "/${hostname}/${hostname}:/${hostname}/${hostname}:ro"
    "/${hostname}/restore:/${hostname}/restore"
    "/${hostname}/dumps:/${hostname}/dumps:ro"
  ];
}
