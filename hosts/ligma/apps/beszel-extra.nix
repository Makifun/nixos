{ config, ... }:
let
  hostname = config.networking.hostName;
in
{
  systemd.tmpfiles.rules = [
    "d '/nicememe/.beszelnicememe'       0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/nicememe/.beszelnicememe:/extra-filesystems/nicememe__nicememe:ro"
  ];

  networking.firewall.extraInputRules = ''
    tcp dport 45876 ip saddr 10.10.10.0/24 accept comment "Beszel agent (hub on ligma reaches LAN agents)"
  '';
}
