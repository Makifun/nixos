{ lib, ... }:
let
  backrestPort = 9898;
in
{
  virtualisation.oci-containers.containers.backrest = {
    ports = lib.mkForce [ "127.0.0.1:${toString backrestPort}:9898" ];
  };
}
