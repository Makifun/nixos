{
  config,
  pkgs,
  hosts,
  ...
}:
let
  # Build from source with two patches to the vendored go-plex-client:
  # 1. Add X-Plex-Token as a URL query parameter (Plex requires it for WS auth).
  # 2. Honor SKIP_TLS_VERIFICATION for the WebSocket dialer (self-signed cert).
  plex-exporter = pkgs.buildGoModule {
    pname = "prometheus-plex-exporter";
    version = "3e7a4da";

    src = pkgs.fetchzip {
      url = "https://github.com/timothystewart6/prometheus-plex-exporter/archive/3e7a4da6306cebcaff499dca055c91dd1afe55fd.tar.gz";
      sha256 = "1n4064ban8xs6cax12fiqkffki7w2yznrpqg3mvrg11kqvqjzqwc";
    };

    # Use the vendor/ directory already present in the source.
    vendorHash = null;

    subPackages = [ "cmd/prometheus-plex-exporter" ];

    patches = [ ./plex-exporter-websocket.patch ];
  };
in
{
  sops.secrets = {
    plex-trash-plex-token.sopsFile = ../secrets.yaml;
    plex-trash-plex-url.sopsFile = ../secrets.yaml;
  };

  sops.templates."plex-exporter.env".content = ''
    PLEX_TOKEN=${config.sops.placeholder."plex-trash-plex-token"}
    PLEX_SERVER=${config.sops.placeholder."plex-trash-plex-url"}
  '';

  systemd.services.plex-exporter = {
    description = "Prometheus Plex Exporter";
    after = [
      "podman-plex.service"
      "network-online.target"
    ];
    wants = [
      "podman-plex.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      EnvironmentFile = config.sops.templates."plex-exporter.env".path;
      Environment = [
        "SKIP_TLS_VERIFICATION=true"
        "TZ=Europe/Stockholm"
      ];
      ExecStartPre = pkgs.writeShellScript "plex-exporter-wait" ''
        for i in $(seq 1 30); do
          status=$(${pkgs.curl}/bin/curl -s -o /dev/null -w "%{http_code}" http://localhost:32400/ 2>/dev/null)
          [ -n "$status" ] && [ "$status" != "503" ] && exit 0
          echo "plex not ready (status=$status), retry $i/30"
          sleep 10
        done
        echo "plex did not become ready in 5 minutes"
        exit 1
      '';
      ExecStart = "${plex-exporter}/bin/prometheus-plex-exporter";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Allow Prometheus on ligma to scrape port 9000.
  networking.firewall.extraInputRules = ''
    ip saddr ${hosts.ligma} tcp dport 9000 accept comment "plex-exporter prometheus scrape"
  '';
}
