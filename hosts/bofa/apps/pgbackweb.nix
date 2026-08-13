{
  config,
  hosts,
  pkgs,
  ...
}:
let
  pgbackwebPort = 8085;
in
{
  sops.secrets.pgbackweb-encryption-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.templates."pgbackweb.env" = {
    content = ''
      PBW_ENCRYPTION_KEY=${config.sops.placeholder.pgbackweb-encryption-key}
      PBW_POSTGRES_CONN_STRING=host=10.88.0.1 port=5432 user=tracearr password=${config.sops.placeholder.timescaledb-tracearr-password} dbname=pgbackweb sslmode=disable
      PBW_LISTEN_PORT=${toString pgbackwebPort}
      TZ=UTC
    '';
  };

  # Create the pgbackweb state database in the existing timescaledb instance.
  systemd.services.pgbackweb-db-setup = {
    description = "Create pgbackweb database in TimescaleDB";
    after = [ "podman-timescaledb.service" ];
    requires = [ "podman-timescaledb.service" ];
    before = [ "podman-pgbackweb.service" ];
    wantedBy = [ "podman-pgbackweb.service" ];
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      until podman exec timescaledb psql -U tracearr -d tracearr -c "SELECT 1" >/dev/null 2>&1; do
        sleep 2
      done
      podman exec timescaledb psql -U tracearr -d tracearr \
        -c "CREATE DATABASE pgbackweb;" 2>/dev/null || true
    '';
  };

  systemd.services.podman-pgbackweb = {
    after = [
      "sops-nix.service"
      "pgbackweb-db-setup.service"
    ];
    wants = [ "sops-nix.service" ];
  };

  virtualisation.oci-containers.containers.pgbackweb = {
    # renovate: datasource=docker depName=eduardolat/pgbackweb
    image = "docker.io/eduardolat/pgbackweb:0.5.1";
    ports = [ "${toString pgbackwebPort}:${toString pgbackwebPort}" ];
    environmentFiles = [ config.sops.templates."pgbackweb.env".path ];
  };

  networking.firewall.extraInputRules = ''
    tcp dport ${toString pgbackwebPort} ip saddr ${hosts.ligma}/32 accept comment "pgbackweb from ligma"
  '';
}
