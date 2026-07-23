{ config, ... }:
let
  # renovate: datasource=docker depName=prompve/prometheus-pve-exporter
  exporterTag = "3.9.0";
in
{
  sops.secrets.proxmox-pve-token-value = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.services.pve-exporter-config = {
    description = "Write pve-exporter config from SOPS secret";
    before = [ "podman-pve-exporter.service" ];
    requiredBy = [ "podman-pve-exporter.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      cat > /run/pve-exporter.yml <<EOF
      default:
        user: prometheus@pve
        token_name: prometheus
        token_value: $(tr -d '\n' < ${config.sops.secrets.proxmox-pve-token-value.path})
        verify_ssl: true
      EOF
      chmod 400 /run/pve-exporter.yml
    '';
  };

  virtualisation.oci-containers.containers.pve-exporter = {
    image = "prompve/prometheus-pve-exporter:${exporterTag}";
    volumes = [ "/run/pve-exporter.yml:/etc/pve-exporter/pve.yml:ro" ];
    cmd = [ "--config.file=/etc/pve-exporter/pve.yml" ];
    ports = [ "127.0.0.1:9221:9221" ];
  };
}
