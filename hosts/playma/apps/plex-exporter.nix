{ config, hosts, ... }:
{
  sops.secrets = {
    plex-trash-plex-token.sopsFile = ../secrets.yaml;
    plex-trash-plex-url.sopsFile = ../secrets.yaml;
  };

  sops.templates."plex-exporter.env".content = ''
    PLEX_TOKEN=${config.sops.placeholder."plex-trash-plex-token"}
  '';

  systemd.services.podman-plex-exporter = {
    after = [ "podman-plex.service" ];
    wants = [ "podman-plex.service" ];
  };

  # renovate: datasource=docker depName=ghcr.io/timothystewart6/prometheus-plex-exporter
  virtualisation.oci-containers.containers.plex-exporter = {
    image = "ghcr.io/timothystewart6/prometheus-plex-exporter:latest";
    extraOptions = [ "--network=host" ];
    environmentFiles = [ config.sops.templates."plex-exporter.env".path ];
    # Override URL to HTTPS — Plex rejects WebSocket upgrades on plain HTTP.
    # --env takes precedence over --env-file for the same key.
    environment = {
      PLEX_SERVER = "https://localhost:32400";
      SKIP_TLS_VERIFICATION = "true";
      TZ = "Europe/Stockholm";
    };
  };

  # Allow Prometheus on ligma to scrape port 9000.
  networking.firewall.extraInputRules = ''
    ip saddr ${hosts.ligma} tcp dport 9000 accept comment "plex-exporter prometheus scrape"
  '';
}
