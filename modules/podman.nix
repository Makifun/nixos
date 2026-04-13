{ ... }:
{
  # Trust all podman bridge interfaces so aardvark-dns can bind on each
  # network's gateway and containers can query DNS. These are host-only
  # bridges — external traffic cannot arrive on podman* interfaces.
  networking.firewall.extraInputRules = ''
    iifname "podman*" accept comment "trust all podman bridge interfaces"
  '';

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
