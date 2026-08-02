{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  backrest.extraPaths = [ "/${hostname}/dumps" ];

  virtualisation.oci-containers.containers.backrest.volumes = [
    "/${hostname}/dumps:/${hostname}/dumps:ro"
  ];
}
