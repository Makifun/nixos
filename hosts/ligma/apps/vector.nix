{ pkgs, ... }:
{
  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      api = {
        enabled = true;
        address = "127.0.0.1:8686";
      };

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
          .host          = "ligma"
          .short_message = to_string(.MESSAGE) ?? "<no message>"
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

      sinks.debug_file = {
        type   = "file";
        inputs = [ "remap" ];
        path   = "/tmp/vector-debug.json";
        encoding.codec = "json";
      };
    };
  };
}
