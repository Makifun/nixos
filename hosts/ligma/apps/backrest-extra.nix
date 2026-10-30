{ lib, ... }:
let
  backrestPort = 9898;
in
{
  # Renovate's cache is rebuilt on demand and churns every run.
  backrest.excludePaths = [ "/ligma/ligma/renovate" ];

  virtualisation.oci-containers.containers.backrest = {
    ports = lib.mkForce [ "127.0.0.1:${toString backrestPort}:9898" ];
  };
}
