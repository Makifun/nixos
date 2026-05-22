{ pkgs, ... }:
let
  # renovate: datasource=docker depName=timberio/vector
  vectorTag = "0.55.0-debian";
in
{
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/vector' 0755 root root - -"
  ];

  environment.etc."vector/config.json".text = builtins.toJSON {
    data_dir = "/var/lib/vector";

    sources.all_journal = {
      type              = "journald";
      journal_directory = "/var/log/journal";
      # Exclude Graylog stack and Vector itself to prevent feedback loops.
      exclude_units = [
        "podman-graylog.service"
        "podman-mongodb.service"
        "podman-datanode.service"
        "podman-vector.service"
      ];
    };

    transforms.remap = {
      type   = "remap";
      inputs = [ "all_journal" ];
      source = ''
        # Drop distribution registry OTEL trace spam.
        if starts_with(string(.SYSLOG_IDENTIFIER) ?? "", "dist-") &&
           contains(string(.message) ?? "", "level=debug") {
          abort
        }

        .host          = "ligma"
        .short_message = string(.message) ?? "<no message>"
        .level         = if exists(.PRIORITY) { to_int(.PRIORITY) ?? 6 } else { 6 }

        if exists(.CONTAINER_NAME)    { .container_name    = string(.CONTAINER_NAME)    ?? "" }
        if exists(._SYSTEMD_UNIT)     { .systemd_unit      = string(._SYSTEMD_UNIT)     ?? "" }
        if exists(.SYSLOG_IDENTIFIER) { .syslog_identifier = string(.SYSLOG_IDENTIFIER) ?? "" }
      '';
    };

    sinks.graylog = {
      type    = "socket";
      inputs  = [ "remap" ];
      address = "127.0.0.1:12201";
      mode    = "udp";
      encoding.codec = "gelf";
    };
  };

  # Wait for Graylog's GELF UDP port before starting.
  # UDP connected sockets enter a permanent error state on ECONNREFUSED and
  # won't recover without a socket recreate (i.e. restart). The wait script
  # avoids the race at boot; timeout after 5 min so Vector still starts if
  # Graylog is absent (sink will log errors gracefully).
  systemd.services.podman-vector = {
    after = [ "podman-graylog.service" ];
    wants = [ "podman-graylog.service" ];
    serviceConfig.ExecStartPre = toString (pkgs.writeShellScript "wait-graylog-gelf" ''
      elapsed=0
      until ${pkgs.iproute2}/bin/ss -ulnp | grep -q ':12201 '; do
        if [ "$elapsed" -ge 300 ]; then
          echo "Timed out waiting for Graylog GELF UDP port 12201" >&2
          exit 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
      done
    '');
  };

  virtualisation.oci-containers.containers.vector = {
    image        = "docker.io/timberio/vector:${vectorTag}";
    # Host networking required — sink targets 127.0.0.1:12201 (Graylog GELF on host loopback).
    extraOptions = [ "--network=host" ];
    cmd          = [ "--config" "/etc/vector/config.json" ];
    volumes = [
      "/etc/vector/config.json:/etc/vector/config.json:ro"
      "/var/log/journal:/var/log/journal:ro"
      "/run/log/journal:/run/log/journal:ro"
      "/etc/machine-id:/etc/machine-id:ro"
      "/ligma/ligma/vector:/var/lib/vector"
    ];
  };
}
