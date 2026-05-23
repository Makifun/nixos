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
    # Socket required by prometheus-podman-exporter container.
    dockerSocket.enable = true;
  };

  environment.etc."alloy/config.alloy".text = ''
    // ── Journal: Kernel logs ───────────────────────────────────────────────────

    loki.relabel "kernel" {
      forward_to = []
      rule {
        source_labels = ["__journal__transport"]
        regex         = "kernel"
        action        = "keep"
      }
      rule {
        target_label = "job"
        replacement  = "${hostname}-kernel"
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

    loki.source.journal "kernel" {
      relabel_rules = loki.relabel.kernel.rules
      forward_to    = [loki.write.loki.receiver]
    }

    // ── Journal: Audit logs ────────────────────────────────────────────────────

    loki.relabel "audit" {
      forward_to = []
      rule {
        source_labels = ["__journal__transport"]
        regex         = "audit"
        action        = "keep"
      }
      rule {
        target_label = "job"
        replacement  = "${hostname}-audit"
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

    loki.source.journal "audit" {
      relabel_rules = loki.relabel.audit.rules
      forward_to    = [loki.write.loki.receiver]
    }

    // ── Journal: Syslog + Podman container logs ────────────────────────────────
    // Drops kernel/audit (handled by dedicated sources above).
    // Routes Podman container logs to job="${hostname}-podman-<container>"
    // by detecting _SYSTEMD_UNIT=podman-*.service entries.

    loki.relabel "syslog" {
      forward_to = []

      rule {
        source_labels = ["__journal__transport"]
        regex         = "kernel|audit"
        action        = "drop"
      }
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
      rule {
        target_label = "job"
        replacement  = "${hostname}-syslog"
      }
      // Extract container name from podman-<name>.service unit name.
      rule {
        source_labels = ["__journal__systemd_unit"]
        regex         = "podman-(.+)\\.service"
        target_label  = "container"
      }
      // If container label is set, override job to <hostname>-podman-<container>.
      rule {
        source_labels = ["container"]
        regex         = "(.+)"
        target_label  = "job"
        replacement   = "${hostname}-podman-$1"
      }
    }

    loki.source.journal "syslog" {
      relabel_rules = loki.relabel.syslog.rules
      forward_to    = [loki.write.loki.receiver]
    }

    // ── Loki write endpoint ────────────────────────────────────────────────────

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

    // ── Podman container metrics via prometheus-podman-exporter ───────────────

    prometheus.scrape "podman_exporter" {
      targets    = [{"__address__" = "127.0.0.1:9882"}]
      job_name   = "podman"
      forward_to = [prometheus.relabel.podman_instance.receiver]
    }

    prometheus.relabel "podman_instance" {
      forward_to = [prometheus.remote_write.prometheus.receiver]
      rule {
        target_label = "instance"
        replacement  = "${hostname}"
      }
    }

    // ── Prometheus remote write ────────────────────────────────────────────────

    prometheus.remote_write "prometheus" {
      endpoint {
        url = "${prometheusUrl}"
      }
      external_labels = { host = "${hostname}" }
    }
  '';

  # renovate: datasource=docker depName=quay.io/navidys/prometheus-podman-exporter
  # podman-exporter uses libpod directly → needs the Podman socket.
  # Runs as root (required for rootful Podman socket access).
  virtualisation.oci-containers.containers.podman-exporter = {
    image        = "quay.io/navidys/prometheus-podman-exporter:v1.21.0";
    ports        = [ "127.0.0.1:9882:9882" ];
    volumes      = [ "/run/podman/podman.sock:/run/podman/podman.sock" ];
    environment  = { CONTAINER_HOST = "unix:///run/podman/podman.sock"; };
    extraOptions = [ "-u" "root" "--security-opt" "label=type:container_runtime_t" ];
    cmd          = [ "--collector.enable-all" ];
  };

  systemd.services.podman-podman-exporter = {
    after = [ "podman.socket" ];
    wants = [ "podman.socket" ];
  };

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
