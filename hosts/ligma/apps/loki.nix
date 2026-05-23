{ ... }:
let
  lokiPort  = 3100;
  alloyPort = 12345;
  lokiBase  = "/ligma/ligma/loki";
  # renovate: datasource=docker depName=grafana/loki
  lokiTag  = "3.4.2";
  # renovate: datasource=docker depName=grafana/alloy
  alloyTag = "v1.8.3";
in
{
  # ── Config files ─────────────────────────────────────────────────────────────

  environment.etc."loki/config.yaml".text = ''
    auth_enabled: false

    server:
      http_listen_port: ${toString lokiPort}
      grpc_listen_port: 9096

    common:
      instance_addr: 127.0.0.1
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory

    query_range:
      results_cache:
        cache:
          embedded_cache:
            enabled: true
            max_size_mb: 100

    schema_config:
      configs:
        - from: "2024-10-01"
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h

    limits_config:
      reject_old_samples: false
  '';

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

    loki.source.journal "ligma" {
      forward_to    = [loki.write.local.receiver]
      relabel_rules = loki.relabel.journal.rules
    }

    loki.write "local" {
      endpoint {
        url = "http://127.0.0.1:${toString lokiPort}/loki/api/v1/push"
      }
      external_labels = { host = "ligma" }
    }

    // ── Node metrics (scrape existing node_exporter) → Prometheus ──────────────

    prometheus.scrape "node" {
      targets    = [{"__address__" = "127.0.0.1:9100"}]
      job_name   = "node"
      forward_to = [prometheus.remote_write.local.receiver]
    }

    prometheus.remote_write "local" {
      endpoint {
        url = "http://127.0.0.1:9090/api/v1/write"
      }
    }
  '';

  # ── Storage ───────────────────────────────────────────────────────────────────
  # Loki container runs as uid 10001 (loki user in the grafana/loki image).

  systemd.tmpfiles.rules = [
    "d '${lokiBase}'        0750 10001 10001 - -"
    "d '${lokiBase}/chunks' 0750 10001 10001 - -"
    "d '${lokiBase}/rules'  0750 10001 10001 - -"
  ];

  # ── Containers ────────────────────────────────────────────────────────────────

  virtualisation.oci-containers.containers = {
    loki = {
      image   = "docker.io/grafana/loki:${lokiTag}";
      ports   = [ "127.0.0.1:${toString lokiPort}:${toString lokiPort}" ];
      volumes = [
        "/etc/loki/config.yaml:/etc/loki/config.yaml:ro"
        "${lokiBase}:/loki"
      ];
      cmd = [ "-config.file=/etc/loki/config.yaml" ];
    };

    alloy = {
      image        = "docker.io/grafana/alloy:${alloyTag}";
      extraOptions = [ "--network=host" ];
      volumes      = [
        "/etc/alloy/config.alloy:/etc/alloy/config.alloy:ro"
        "/var/log/journal:/var/log/journal:ro"
        "/run/log/journal:/run/log/journal:ro"
        "/etc/machine-id:/etc/machine-id:ro"
      ];
      cmd = [
        "run"
        "--server.http.listen-addr=0.0.0.0:${toString alloyPort}"
        "/etc/alloy/config.alloy"
      ];
    };
  };

  # Alloy needs Loki up before it starts pushing logs.
  systemd.services.podman-alloy = {
    after = [ "podman-loki.service" ];
    wants = [ "podman-loki.service" ];
  };
}
