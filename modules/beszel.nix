{
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  beszelBase = "/${hostname}/${hostname}/beszel";
  # renovate: datasource=docker depName=henrygd/beszel
  beszelTag = "0.18.7";
in
{
  sops.secrets.beszel_agent_key = {
    format = "yaml";
    sopsFile = ../hosts + "/${hostname}/secrets.yaml";
  };

  systemd.tmpfiles.rules = [
    "d '${beszelBase}/data'         0755 root root - -"
    "d '/.beszelroot'               0755 root root - -"
    "d '/nix/.beszelnixos'          0755 root root - -"
    "d '/persist/.beszelpersist'    0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent = {
    image = "henrygd/beszel-agent:${beszelTag}";
    environment = {
      PORT = "45876";
      FILESYSTEM = "/extra-filesystems/root__root";
    };
    environmentFiles = [ config.sops.secrets.beszel_agent_key.path ];
    extraOptions = [ "--network=host" ];
    volumes = [
      "/run/podman/podman.sock:/var/run/docker.sock:ro"
      "/.beszelroot:/extra-filesystems/root__root:ro"
      "/nix/.beszelnixos:/extra-filesystems/nixos__nix:ro"
      "/persist/.beszelpersist:/extra-filesystems/persist__persist:ro"
    ];
  };

  systemd.services.podman-beszel-agent.after = [ "podman.socket" ];
  systemd.services.podman-beszel-agent.requires = [ "podman.socket" ];

  networking.firewall.extraInputRules = ''
    tcp dport 45876 ip saddr ${hosts.ligma}/32 accept comment "Beszel agent"
  '';
}
