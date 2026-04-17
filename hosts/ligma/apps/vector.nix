{ pkgs, ... }:
{
  services.vector = {
    enable = true;
    journaldAccess = true;
    settings = {
      sources.authentik_journal = {
        type    = "journald";
        include_units = [
          "podman-authentik-worker.service"
          "podman-authentik-server.service"
        ];
      };

      transforms.authentik_remap = {
        type   = "remap";
        inputs = [ "authentik_journal" ];
        source = ''
          .host    = "ligma"
          .facility = 1
          .level    = if exists(.PRIORITY) {
            to_int!(.PRIORITY)
          } else {
            6
          }
        '';
      };

      sinks.graylog = {
        type     = "gelf";
        inputs   = [ "authentik_remap" ];
        endpoint = "udp://127.0.0.1:12201";
      };
    };
  };
}
