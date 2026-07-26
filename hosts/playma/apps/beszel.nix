{ config, ... }:
let
  beszelBase = "/playma/playma/beszel";
  # renovate: datasource=docker depName=henrygd/beszel
  beszelTag = "0.18.7";
in
{
  systemd.tmpfiles.rules = [
    "d '${beszelBase}/data'          0755 root root - -"
    "d '/.beszelroot'                0755 root root - -"
    "d '/nix/.beszelnixos'           0755 root root - -"
    "d '/playma/.beszelplayma'       0755 root root - -"
    "d '/persist/.beszelpersist'     0755 root root - -"
    "d '/transcode/.beszeltranscode' 0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Agent — monitors playma itself.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.beszel-agent = {
    image = "henrygd/beszel-agent:${beszelTag}";
    environment = {
      PORT = "45876";
      FILESYSTEM = "/extra-filesystems/root__root";
    };
    environmentFiles = [ config.sops.secrets.beszel_agent_key.path ];
    extraOptions = [ "--network=host" ];
    # Mount the Podman socket so Beszel can report container stats.
    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock:ro"
      "/.beszelroot:/extra-filesystems/root__root:ro"
      "/nix/.beszelnixos:/extra-filesystems/nixos__nix:ro"
      "/playma/.beszelplayma:/extra-filesystems/playma__playma:ro"
      "/persist/.beszelpersist:/extra-filesystems/persist__persist:ro"
      "/transcode/.beszeltranscode:/extra-filesystems/transcode__transcode:ro"
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
    tcp dport 45876 ip saddr 10.10.10.13/32 accept comment "Beszel agent"
  '';
}
