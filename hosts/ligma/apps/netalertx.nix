{ config, pkgs, ... }:
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

  sops.secrets.netalertx-gotify-token = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # ---------------------------------------------------------------------------
  # NetAlertX initial config
  # Written only on first boot (if app.conf absent). UI changes persist.
  # To force a re-write: rm /ligma/ligma/netalertx/config/app.conf + restart.
  # Notifications: NetAlertX → Apprise server (127.0.0.1:8097) → Gotify.
  # ---------------------------------------------------------------------------
  systemd.services.netalertx-config = {
    description = "Write NetAlertX initial app.conf";
    before      = [ "podman-netalertx.service" ];
    requiredBy  = [ "podman-netalertx.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils pkgs.gnused ];
    script = ''
      CONFIG="${netalertxBase}/config/app.conf"
      if [ ! -f "$CONFIG" ]; then
        TOKEN=$(tr -d '\n' < ${config.sops.secrets.netalertx-gotify-token.path})
        cat > "$CONFIG" <<'NETALERTX_CONF'
LOADED_PLUGINS=['ARPSCAN','AVAHISCAN','CSVBCKP','DBCLNP','DIGSCAN','INTRNT','MAINT','NEWDEV','NBTSCAN','NSLOOKUP','NTFPRCS','SETPWD','SMTP','SYNC','VNDRPDT','WORKFLOWS','UI','CUSTPROP','APPRISE']
SCAN_SUBNETS=['10.10.10.0/24 --interface=ens18']
TIMEZONE='Europe/Stockholm'
REPORT_DASHBOARD_URL='https://netalertx.makifun.se'
ARPSCAN_RUN='schedule'
ARPSCAN_RUN_SCHD='*/5 * * * *'
APPRISE_RUN='on_notification'
APPRISE_HOST='http://127.0.0.1:8097/notify'
APPRISE_TARGETTYPE='url'
APPRISE_URL='gotifys://gotify.makifun.se/__TOKEN__'
APPRISE_PAYLOAD='text'
NETALERTX_CONF
        sed -i "s/__TOKEN__/$TOKEN/" "$CONFIG"
      fi
    '';
  };

  # ---------------------------------------------------------------------------
  # NetAlertX — network presence monitor
  # Scans LAN via arp-scan; notifies via Apprise → Gotify on new/returning devices.
  # Host networking required for ARP scans to reach LAN interfaces directly.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.netalertx = {
    image = "ghcr.io/jokob-sk/netalertx:${netalertxTag}";
    volumes = [
      "${netalertxBase}/config:/data/config"
      "${netalertxBase}/db:/data/db"
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
