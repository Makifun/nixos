{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  systemd.tmpfiles.rules = [
    "d '/${hostname}/.beszel${hostname}' 0755 root root - -"
    "d '/nicememe/.beszelnicememe'       0755 root root - -"
    "d '/slowmeme/.beszelslowmeme'       0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/${hostname}/.beszel${hostname}:/extra-filesystems/${hostname}__${hostname}:ro"
    "/nicememe/.beszelnicememe:/extra-filesystems/nicememe__nicememe:ro"
    "/slowmeme/.beszelslowmeme:/extra-filesystems/slowmeme__slowmeme:ro"
  ];

  networking.firewall.extraInputRules = ''
    tcp dport 45876 ip saddr 10.10.10.0/24 accept comment "Beszel agent (hub on ligma reaches LAN agents)"
  '';
}
