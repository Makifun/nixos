{
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
in
{
  virtualisation.oci-containers.containers.docker-socket-proxy = {
    # renovate: datasource=docker depName=ghcr.io/tecnativa/docker-socket-proxy
    image = "ghcr.io/tecnativa/docker-socket-proxy:0.5.0";
    environment = {
      CONTAINERS = "1";
      INFO = "1";
      VERSION = "1";
      STATS = "1";
    };
    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock:ro"
    ];
    ports = [ "${hosts.${hostname}}:2375:2375" ];
  };

  networking.firewall.extraInputRules = ''
    tcp dport 2375 ip saddr ${hosts.ligma} accept comment "docker-socket-proxy for homepage on ligma"
  '';
}
