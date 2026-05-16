{ pkgs, ... }:
{
  # Wait for Graylog's GELF UDP port before starting Vector.
  # Connected UDP sockets enter a permanent error state on ECONNREFUSED and
  # won't recover without a socket recreate (i.e. restart). The wait script
  # avoids the race at boot; timeout after 5 min so Vector still starts if
  # Graylog is absent (sink will log errors gracefully).
  systemd.services.vector = {
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

  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      sources.all_journal = {
        type = "journald";
        # Exclude the Graylog stack itself and Vector to prevent feedback loops.
        exclude_units = [
          "podman-graylog.service"
          "podman-mongodb.service"
          "podman-datanode.service"
          "vector.service"
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

          # Promote journald metadata as top-level GELF fields for Graylog filtering.
          if exists(.CONTAINER_NAME) {
            .container_name = string(.CONTAINER_NAME) ?? ""
          }
          if exists(._SYSTEMD_UNIT) {
            .systemd_unit = string(._SYSTEMD_UNIT) ?? ""
          }
          if exists(.SYSLOG_IDENTIFIER) {
            .syslog_identifier = string(.SYSLOG_IDENTIFIER) ?? ""
          }
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
  };
}
