{ config, pkgs, ... }:
let
  # renovate: datasource=docker depName=aceberg/watchyourlan
  wylTag  = "2.1.4";
  wylBase = "/ligma/ligma/watchyourlan";
in
{
  systemd.tmpfiles.rules = [
    "d '${wylBase}' 0755 root root - -"
  ];

  sops.secrets.watchyourlan-gotify-token = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # ---------------------------------------------------------------------------
  # WatchYourLAN initial config
  # Written only on first boot (if config_v2.yaml absent). UI changes persist.
  # To force re-write: rm /ligma/ligma/watchyourlan/config_v2.yaml + restart.
  # ---------------------------------------------------------------------------
  systemd.services.watchyourlan-config = {
    description = "Write WatchYourLAN initial config_v2.yaml";
    before      = [ "podman-watchyourlan.service" ];
    requiredBy  = [ "podman-watchyourlan.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils pkgs.gnused ];
    script = ''
      CONFIG="${wylBase}/config_v2.yaml"
      if [ ! -f "$CONFIG" ]; then
        TOKEN=$(tr -d '\n' < ${config.sops.secrets.watchyourlan-gotify-token.path})
        cat > "$CONFIG" <<'WYL_CONF'
color: dark
host: 0.0.0.0
ifaces: ens18
log_level: info
port: "8840"
shoutrrr_url: "gotify://gotify.makifun.se/__TOKEN__/?title=WatchYourLAN"
theme: sand
timeout: 60
trim_hist: 48
use_db: sqlite
WYL_CONF
        sed -i "s/__TOKEN__/$TOKEN/" "$CONFIG"
      fi
    '';
  };

  # ---------------------------------------------------------------------------
  # WatchYourLAN — lightweight network presence monitor
  # ARP-scans LAN; notifies via Gotify (Shoutrrr) on new/returning devices.
  # Host networking required for ARP scans. Web UI at :8840.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.watchyourlan = {
    image = "ghcr.io/aceberg/watchyourlan:${wylTag}";
    volumes = [
      "${wylBase}:/data/WatchYourLAN"
    ];
    environment = {
      TZ    = "Europe/Stockholm";
      IFACES = "ens18";
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
      watchyourlan = {
        rule        = "Host(`watchyourlan.makifun.se`)";
        entryPoints = [ "websecure" ];
        service     = "watchyourlan-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      "watchyourlan-outpost" = {
        rule        = "Host(`watchyourlan.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."watchyourlan-svc".loadBalancer.servers = [{ url = "http://127.0.0.1:8840"; }];
  };
}
