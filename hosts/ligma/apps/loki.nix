{
  config,
  baseFacts,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  lokiPort = 3100;
  lokiBase = "/${hostname}/${hostname}/loki";
  # renovate: datasource=docker depName=grafana/loki
  lokiTag = "3.7.4";
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

  virtualisation.oci-containers.containers.loki = {
    image = "docker.io/grafana/loki:${lokiTag}";
    ports = [ "127.0.0.1:${toString lokiPort}:${toString lokiPort}" ];
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

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      loki-outpost = {
        rule = "Host(`loki.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      loki-push = {
        rule = "Host(`loki.${baseFacts.domainName}`) && PathPrefix(`/loki/api/v1/push`)";
        priority = 10;
        entryPoints = [ "websecure" ];
        service = "loki-svc";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      loki = {
        rule = "Host(`loki.${baseFacts.domainName}`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "loki-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."loki-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString lokiPort}"; }
    ];
  };

  ligma.dnsRecords."loki.${baseFacts.domainName}".value = hosts.ligma;
}
