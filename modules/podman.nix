{ ... }:
{
  # Trust podman bridge interfaces so aardvark-dns can bind on the gateway
  # address and containers can query DNS (10.89.x.x:53).
  networking.firewall.trustedInterfaces = [ "podman0" "podman1" "podman2" ];

  virtualisation = {
    containers = {
      enable = true;
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
