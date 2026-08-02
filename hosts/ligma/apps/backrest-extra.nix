{ config, lib, ... }:
let
  hostname = config.networking.hostName;
  backrestPort = 9898;
in
{
  backrest.scheduleHour = 1;
  backrest.extraPaths = [ "/${hostname}/sugma" ];

  virtualisation.oci-containers.containers.backrest = {
    ports = lib.mkForce [ "127.0.0.1:${toString backrestPort}:9898" ];
    volumes = [
      "/${hostname}/sugma:/${hostname}/sugma:ro"
    ];
  };
}
