{ config, ... }:
{
  sops.secrets.beszel_agent_key.sopsFile = ../secrets.yaml;

  # Ligma-specific extra filesystems for disk monitoring.
  systemd.tmpfiles.rules = [
    "d '/ligma/.beszelligma'          0755 root root - -"
    "d '/nicememe/.beszelnicememe'    0755 root root - -"
    "d '/slowmeme/.beszelslowmeme'    0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent.volumes = [
    "/ligma/.beszelligma:/extra-filesystems/ligma__ligma:ro"
    "/nicememe/.beszelnicememe:/extra-filesystems/nicememe__nicememe:ro"
    "/slowmeme/.beszelslowmeme:/extra-filesystems/slowmeme__slowmeme:ro"
  ];

  # Hub is local (Podman container) — already covered by iifname "podman*" accept
  # in modules/podman.nix. Broader LAN rule lets the hub reach other hosts' agents
  # and allows jonny/others to be monitored from this hub.
  networking.firewall.extraInputRules = ''
    tcp dport 45876 ip saddr 10.10.10.0/24 accept comment "Beszel agent (hub on ligma reaches LAN agents)"
  '';
}
