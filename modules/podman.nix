{ ... }:
{
  # Trust all podman bridge interfaces so aardvark-dns can bind on each
  # network's gateway and containers can query DNS. These are host-only
  # bridges — external traffic cannot arrive on podman* interfaces.
  networking.firewall.extraInputRules = ''
    iifname "podman*" accept comment "trust all podman bridge interfaces"
  '';

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/containers";
      user = "root";
      group = "root";
      mode = "0750";
    }
  ];

  virtualisation = {
    containers = {
      enable = true;
    };
    podman = {
      enable = true;
      dockerCompat = true;
      # Enable the socket so tools like beszel-agent can query container stats.
      # Creates /run/podman/podman.sock (group: podman) and symlinks /run/docker.sock.
      dockerSocket.enable = true;
      defaultNetwork.settings.dns_enabled = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };
}
