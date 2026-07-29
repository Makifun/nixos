{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  backrest.scheduleHour = 5;

  virtualisation.oci-containers.containers.backrest.volumes = [
    "/${hostname}/${hostname}:/${hostname}/${hostname}:ro"
    "/${hostname}/restore:/${hostname}/restore"
  ];
}
