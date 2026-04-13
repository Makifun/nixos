{ ... }:
{
  # Trust podman bridge interfaces so aardvark-dns can bind on the gateway
  # address and containers can query DNS (10.89.x.x:53).
  networking.firewall.trustedInterfaces = [ "podman0" "podman1" ];

  # aardvark-dns listens on every network's gateway, but querying the default
  # network gateway (10.88.0.1) resolves names across ALL Podman networks.
  # Custom networks get their own gateway assigned dynamically; by hardcoding
  # 10.88.0.1 in a shared resolv.conf and mounting it into every container,
  # DNS is consistent regardless of which network a container is on.
  environment.etc."podman-resolv.conf".text = ''
    nameserver 10.88.0.1
    search dns.podman
    options edns0
  '';

  virtualisation = {
    containers = {
      enable = true;
      containersConf.settings.containers.volumes = [
        "/etc/podman-resolv.conf:/etc/resolv.conf:ro"
      ];
    };
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };
}
