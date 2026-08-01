{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  systemd.tmpfiles.rules = [
    "d '/${hostname}/.beszel${hostname}' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/${hostname}/.beszel${hostname}:/extra-filesystems/${hostname}__${hostname}:ro"
  ];
}
