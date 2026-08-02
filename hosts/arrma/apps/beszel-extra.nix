{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  systemd.tmpfiles.rules = [
    "d '/nicememe/.beszelnicememe'             0755 root root - -"
    "d '/slowmeme/.beszelslowmeme'             0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/nicememe/.beszelnicememe:/extra-filesystems/nicememe__nicememe:ro"
    "/slowmeme/.beszelslowmeme:/extra-filesystems/slowmeme__slowmeme:ro"
  ];
}
