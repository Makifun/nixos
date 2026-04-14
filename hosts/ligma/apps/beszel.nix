{ config, ... }:
let
  beszelPort = 8095;
  beszelBase = "/ligma/ligma/beszel";
in
{
  systemd.tmpfiles.rules = [
    "d '${beszelBase}/data' 0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Hub
  # Stores its PocketBase database in beszelBase/data.
  # Web UI served on localhost:8095 → Traefik only.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.beszel = {
    image   = "henrygd/beszel:latest";
    ports   = [ "127.0.0.1:${toString beszelPort}:8090" ];
    volumes = [ "${beszelBase}/data:/beszel_data" ];
  };

  # ---------------------------------------------------------------------------
  # Agent — monitors ligma itself.
  #
  # Runs with host networking so it can see host interfaces and is reachable
  # by the hub container. The hub connects OUT to each agent.
  #
  # In the Beszel UI, add ligma with:
  #   Host: 10.88.0.1   (Podman default-network gateway = the host)
  #   Port: 45876
  # Beszel will show a KEY value — store it in SOPS secrets.yaml as:
  #   beszel_agent_key: "KEY=<value>"
  #
  # Bootstrap order:
  #   1. Deploy this config (hub starts; agent fails until KEY exists — OK)
  #   2. Open https://beszel.makifun.se and create admin account
  #      (or migrate data from jonny: copy /path/to/beszel/data → beszelBase/data)
  #   3. Add system "ligma", host 10.88.0.1, port 45876 → copy the KEY shown
  #   4. sops hosts/ligma/secrets.yaml → add: beszel_agent_key: "KEY=<value>"
  #   5. Redeploy → agent starts and hub shows ligma as connected
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.beszel-agent = {
    image            = "henrygd/beszel-agent:latest";
    environment      = { PORT = "45876"; };
    environmentFiles = [ config.sops.secrets.beszel_agent_key.path ];
    extraOptions     = [ "--network=host" ];
    # Mount the Podman socket so Beszel can report container stats.
    # /run/docker.sock is the symlink created by dockerSocket.enable in podman.nix.
    volumes          = [ "/run/docker.sock:/var/run/docker.sock:ro" ];
  };

  sops.secrets.beszel_agent_key = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # The hub→ligma-agent path is already covered by the `iifname "podman*" accept`
  # rule in modules/podman.nix. This opens port 45876 for agents on other LAN
  # hosts (e.g. jonny) so the hub can also monitor those systems.
  # ---------------------------------------------------------------------------
  networking.firewall.extraInputRules = ''
    tcp dport 45876 ip saddr 10.10.10.0/24 accept comment "Beszel agent (hub connects to monitored hosts)"
  '';

  # ---------------------------------------------------------------------------
  # Traefik
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      beszel = {
        rule        = "Host(`beszel.makifun.se`)";
        entryPoints = [ "websecure" ];
        service     = "beszel-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      beszel-outpost = {
        rule        = "Host(`beszel.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."beszel-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString beszelPort}"; }
    ];
  };
}
