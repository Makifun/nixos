{
  baseFacts,
  config,
  pkgs,
  ...
}:
let
  # renovate: datasource=docker depName=ghcr.io/athennamind/opnsense-exporter
  exporterTag = "0.0.17";
in
{
  sops.secrets.opnsense-api-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.secrets.opnsense-api-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Write env file before container starts — SOPS secrets can't be passed
  # directly as env vars to OCI containers.
  systemd.services.opnsense-exporter-env = {
    description = "Write opnsense-exporter env file from SOPS secrets";
    before = [ "podman-opnsense-exporter.service" ];
    requiredBy = [ "podman-opnsense-exporter.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      printf 'OPNSENSE_EXPORTER_OPS_API_KEY=%s\nOPNSENSE_EXPORTER_OPS_API_SECRET=%s\n' \
        "$(tr -d '\n' < ${config.sops.secrets.opnsense-api-key.path})" \
        "$(tr -d '\n' < ${config.sops.secrets.opnsense-api-secret.path})" \
        > /run/opnsense-exporter-env
      chmod 400 /run/opnsense-exporter-env
    '';
  };

  # ---------------------------------------------------------------------------
  # opnsense-exporter — scrapes OPNsense API over HTTPS, exposes Prometheus
  # metrics on localhost:9091. Prometheus scrapes this instead of hitting
  # OPNsense's node_exporter directly, keeping credentials off the firewall.
  # instance-label must match the node_exporter instance label so the Grafana
  # dashboard can join opnsense_* and node_* metrics on $opnsense_instance.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.opnsense-exporter = {
    image = "ghcr.io/athennamind/opnsense-exporter:${exporterTag}";
    environmentFiles = [ "/run/opnsense-exporter-env" ];
    cmd = [
      "--opnsense.protocol=https"
      "--opnsense.address=opnsense.${baseFacts.domainName}"
      "--exporter.instance-label=opnsense.${baseFacts.domainName}"
      "--web.listen-address=:9091"
      "--log.level=info"
    ];
    ports = [ "127.0.0.1:9091:9091" ];
  };
}
