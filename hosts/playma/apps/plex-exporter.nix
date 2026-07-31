{ config, hosts, ... }:
{
  sops.secrets = {
    plex-trash-plex-token.sopsFile = ../secrets.yaml;
    plex-trash-plex-url.sopsFile = ../secrets.yaml;
  };

  sops.templates."plex-exporter.env".content = ''
    PLEX_SERVER=${config.sops.placeholder."plex-trash-plex-url"}
    PLEX_TOKEN=${config.sops.placeholder."plex-trash-plex-token"}
    TZ=Europe/Stockholm
  '';

  # renovate: datasource=docker depName=ghcr.io/timothystewart6/prometheus-plex-exporter
  virtualisation.oci-containers.containers.plex-exporter = {
    image = "ghcr.io/timothystewart6/prometheus-plex-exporter:latest";
    extraOptions = [ "--network=host" ];
    environmentFiles = [ config.sops.templates."plex-exporter.env".path ];
  };

  # Allow Prometheus on ligma to scrape port 9000.
  networking.firewall.extraInputRules = ''
    ip saddr ${hosts.ligma} tcp dport 9000 accept comment "plex-exporter prometheus scrape"
  '';
}
