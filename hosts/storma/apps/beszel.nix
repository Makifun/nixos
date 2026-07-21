{ config, ... }:
let
  beszelBase = "/storma/storma/beszel";
  beszelPort = "45876";
  # renovate: datasource=docker depName=henrygd/beszel
  beszelTag = "0.18.7";
in
{
  systemd.tmpfiles.rules = [
    "d '${beszelBase}/data'         0755 root root - -"
    "d '/storma/.beszelstorma'          0755 root root - -"
    "d '/persist/.beszelpersist'    0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Agent — monitors storma itself.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.beszel-agent = {
    image = "henrygd/beszel-agent:${beszelTag}";
    environment = {
      PORT = beszelPort;
    };
    environmentFiles = [ config.sops.secrets.beszel_agent_key.path ];
    extraOptions = [ "--network=host" ];
    # Mount the Podman socket so Beszel can report container stats.
    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock:ro"
      "/storma/.beszelstorma:/extra-filesystems/storma:ro"
      "/persist/.beszelpersist:/extra-filesystems/persist:ro"
    ];
  };

  # Ensure podman.socket is active before the agent container starts,
  # so /run/podman/podman.sock exists when Podman tries to bind-mount it.
  systemd.services.podman-beszel-agent.after = [ "podman.socket" ];
  systemd.services.podman-beszel-agent.requires = [ "podman.socket" ];

  sops.secrets.beszel_agent_key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  networking.firewall.extraInputRules = ''
    tcp dport ${beszelPort} ip saddr 10.10.10.13/32 accept comment "Beszel agent"
  '';
}
