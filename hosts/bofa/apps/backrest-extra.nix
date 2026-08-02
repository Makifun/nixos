{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  backrest.scheduleHour = 2;
  backrest.extraPaths = [ "/${hostname}/dumps" ];

  virtualisation.oci-containers.containers.backrest.volumes = [
    "/${hostname}/dumps:/${hostname}/dumps:ro"
  ];
}
