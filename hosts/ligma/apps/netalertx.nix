{ ... }:
let
  # renovate: datasource=docker depName=jokob-sk/netalertx registryUrl=https://ghcr.io
  netalertxTag  = "26.5.4";
  netalertxBase = "/ligma/ligma/netalertx";
in
{
  systemd.tmpfiles.rules = [
    "d '${netalertxBase}/config' 0755 root root - -"
    "d '${netalertxBase}/db'     0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # NetAlertX — network presence monitor
  # Scans the LAN via arp-scan and notifies (Gotify) when new/returning devices
  # appear. Host networking required for ARP scans to see LAN interfaces.
  # Web UI: https://netalertx.makifun.se  (first run: configure via UI)
  #   Settings → Plugins → GOTIFY → URL + token
  #   Settings → Scan → SUBNETS → [ '10.10.10.0/24, ens18' ]
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.netalertx = {
    image = "ghcr.io/jokob-sk/netalertx:${netalertxTag}";
    volumes = [
      "${netalertxBase}/config:/app/config"
      "${netalertxBase}/db:/app/db"
    ];
    environment = {
      TZ = "Europe/Stockholm";
    };
    extraOptions = [
      "--network=host"
      "--cap-add=NET_ADMIN"
      "--cap-add=NET_RAW"
    ];
  };

  # ---- Traefik ----------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      netalertx = {
        rule        = "Host(`netalertx.makifun.se`)";
        entryPoints = [ "websecure" ];
        service     = "netalertx-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      "netalertx-outpost" = {
        rule        = "Host(`netalertx.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."netalertx-svc".loadBalancer.servers = [{ url = "http://127.0.0.1:20211"; }];
  };
}
