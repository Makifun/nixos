{ pkgs, ... }:
{
  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      sources.authentik_journal = {
        type          = "journald";
        include_units = [
          "authentik-worker.service"
          "authentik-server.service"
        ];
      };

      transforms.authentik_remap = {
        type   = "remap";
        inputs = [ "authentik_journal" ];
        source = ''
          .host          = "ligma"
          .short_message = string!(.MESSAGE)
          .level         = if exists(.PRIORITY) { to_int!(.PRIORITY) } else { 6 }
        '';
      };

      sinks.graylog = {
        type    = "socket";
        inputs  = [ "authentik_remap" ];
        address = "127.0.0.1:12201";
        mode    = "udp";
        encoding.codec = "gelf";
      };
    };
  };
}
