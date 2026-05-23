{ config, ... }:
let
  hostname      = config.networking.hostName;
  lokiUrl       = "https://loki.makifun.se/loki/api/v1/push";
  prometheusUrl = "https://prometheus.makifun.se/api/v1/write";
  alloyPort     = 12345;
  # renovate: datasource=docker depName=grafana/alloy
  alloyTag = "v1.16.1";
in
{
  # Trust podman bridge interfaces for aardvark-dns.
  networking.firewall.extraInputRules = ''
    iifname "podman*" accept comment "trust all podman bridge interfaces"
  '';

  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  environment.etc."alloy/config.alloy".text = ''
    // ── Journal logs → Loki ────────────────────────────────────────────────────

    loki.relabel "journal" {
      forward_to = []
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal__hostname"]
        target_label  = "host"
      }
      rule {
        source_labels = ["__journal__priority_keyword"]
        target_label  = "level"
      }
    }

    loki.source.journal "system" {
      forward_to    = [loki.write.loki.receiver]
      relabel_rules = loki.relabel.journal.rules
    }

    loki.write "loki" {
      endpoint {
        url = "${lokiUrl}"
      }
      external_labels = { host = "${hostname}" }
    }

    // ── Host metrics via built-in unix exporter → Prometheus ──────────────────
    // Replaces standalone node_exporter. Mounts / as /rootfs for full
    // filesystem visibility. instance label set to hostname for multi-host
    // Grafana dashboards.

    prometheus.exporter.unix "node" {
      rootfs_path = "/rootfs"
    }

    prometheus.relabel "node_instance" {
      forward_to = [prometheus.remote_write.prometheus.receiver]
      rule {
        target_label = "instance"
        replacement  = "${hostname}"
      }
    }

    prometheus.scrape "node" {
      targets    = prometheus.exporter.unix.node.targets
      job_name   = "node"
      forward_to = [prometheus.relabel.node_instance.receiver]
    }

    prometheus.remote_write "prometheus" {
      endpoint {
        url = "${prometheusUrl}"
      }
      external_labels = { host = "${hostname}" }
    }
  '';

  virtualisation.oci-containers.containers.alloy = {
    image        = "docker.io/grafana/alloy:${alloyTag}";
    # host + pid networking required for journal access and full node metrics.
    extraOptions = [ "--network=host" "--pid=host" ];
    volumes = [
      "/etc/alloy/config.alloy:/etc/alloy/config.alloy:ro"
      "/var/log/journal:/var/log/journal:ro"
      "/run/log/journal:/run/log/journal:ro"
      "/etc/machine-id:/etc/machine-id:ro"
      "/:/rootfs:ro,rslave"
    ];
    cmd = [
      "run"
      "--server.http.listen-addr=0.0.0.0:${toString alloyPort}"
      "/etc/alloy/config.alloy"
    ];
  };
}
