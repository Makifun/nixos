{ ... }:
let
  lokiPort = 3100;
  lokiBase = "/ligma/ligma/loki";
  # renovate: datasource=docker depName=grafana/loki
  lokiTag = "3.7.2";
in
{
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

  # Loki container runs as uid 10001 (loki user in the grafana/loki image).
  systemd.tmpfiles.rules = [
    "d '${lokiBase}'        0750 10001 10001 - -"
    "d '${lokiBase}/chunks' 0750 10001 10001 - -"
    "d '${lokiBase}/rules'  0750 10001 10001 - -"
  ];

  # Loki binds to the LAN interface so all hosts can push logs to it.
  # Firewall restricts access to the homelab subnet only.
  networking.firewall.extraInputRules = ''
    ip saddr 10.10.10.0/24 tcp dport ${toString lokiPort} accept comment "loki from LAN"
  '';

  virtualisation.oci-containers.containers.loki = {
    image   = "docker.io/grafana/loki:${lokiTag}";
    ports   = [ "10.10.10.13:${toString lokiPort}:${toString lokiPort}" ];
    volumes = [
      "/etc/loki/config.yaml:/etc/loki/config.yaml:ro"
      "${lokiBase}:/loki"
    ];
    cmd = [ "-config.file=/etc/loki/config.yaml" ];
  };

  # Alloy (defined in common/alloy.nix) needs Loki up first.
  systemd.services.podman-alloy = {
    after = [ "podman-loki.service" ];
    wants = [ "podman-loki.service" ];
  };
}
