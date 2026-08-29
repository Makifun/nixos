{
  config,
  baseFacts,
  hosts,
  lib,
  ...
}:
let
  hostname = config.networking.hostName;
  beszelBase = "/${hostname}/${hostname}/beszel";
  # renovate: datasource=docker depName=henrygd/beszel
  beszelTag = "0.18.8";
in
{
  sops.secrets.beszel_agent_key = {
    format = "yaml";
    sopsFile = ../common/secrets.yaml;
  };

  sops.secrets.beszel_universal_token = {
    format = "yaml";
    sopsFile = ../common/secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '${beszelBase}/data'               0755 root root - -"
    "d '/${hostname}/.beszel${hostname}'  0755 root root - -"
    "d '/.beszelroot'                     0755 root root - -"
    "d '/nix/.beszelnixos'                0755 root root - -"
    "d '/persist/.beszelpersist'          0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel-agent = {
    image = "docker.io/henrygd/beszel-agent:${beszelTag}";
    environment = {
      PORT = "45876";
      FILESYSTEM = "/extra-filesystems/${hostname}__${hostname}";
      # Agent dials the hub itself and self-registers via the universal token
      # (KEY/TOKEN below) — no manual "add system in the UI" step needed for
      # new hosts. PORT/LISTEN above is kept for the hub's legacy pull path.
      # Goes through Traefik (not a raw LAN port) — see the beszel-agent-connect
      # router bypass in hosts/ligma/apps/beszel-server.nix.
      HUB_URL = "https://beszel.${baseFacts.domainName}";
    };
    environmentFiles = [
      config.sops.secrets.beszel_agent_key.path
      config.sops.secrets.beszel_universal_token.path
    ];
    extraOptions = [ "--network=host" ];
    volumes = [
      "/var/run/dbus/system_bus_socket:/var/run/dbus/system_bus_socket:ro"
      "/run/podman/podman.sock:/var/run/docker.sock:ro"
      "/.beszelroot:/extra-filesystems/root__root:ro"
      "/nix/.beszelnixos:/extra-filesystems/nixos__nix:ro"
      "/persist/.beszelpersist:/extra-filesystems/persist__persist:ro"
      "/${hostname}/.beszel${hostname}:/extra-filesystems/${hostname}__${hostname}:ro"
    ];
  };

  systemd.services.podman-beszel-agent.after = [ "podman.socket" ];
  systemd.services.podman-beszel-agent.requires = [ "podman.socket" ];

  networking.firewall.extraInputRules = ''
    tcp dport 45876 ip saddr ${hosts.ligma}/32 accept comment "Beszel agent"
  '';
}
