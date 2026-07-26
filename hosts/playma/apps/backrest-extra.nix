{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  virtualisation.oci-containers.containers.backrest.volumes = [
    "/${hostname}/${hostname}:/${hostname}/${hostname}:ro"
    "/${hostname}/restore:/${hostname}/restore"
  ];
}
