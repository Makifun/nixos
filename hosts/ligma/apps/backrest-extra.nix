{ config, lib, ... }:
let
  hostname = config.networking.hostName;
  backrestPort = 9898;
in
{
  backrest.scheduleHour = 2;
  backrest.extraPaths = [ "/${hostname}/sugma" ];

  virtualisation.oci-containers.containers.backrest = {
    ports = lib.mkForce [ "127.0.0.1:${toString backrestPort}:9898" ];
    volumes = [
      "/${hostname}/${hostname}:/${hostname}/${hostname}:ro"
      "/${hostname}/sugma:/${hostname}/sugma:ro"
      "/${hostname}/restore:/${hostname}/restore"
    ];
  };
}
