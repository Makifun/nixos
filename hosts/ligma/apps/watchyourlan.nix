{
  baseFacts,
  config,
  hosts,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  # renovate: datasource=docker depName=aceberg/watchyourlan
  wylTag = "2.1.4";
  wylBase = "/${hostname}/${hostname}/watchyourlan";
in
{
  sops.secrets.watchyourlan-gotify-token = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '${wylBase}' 0755 root root - -"
  ];

  systemd.services.watchyourlan-config = {
    description = "Write WatchYourLAN initial config_v2.yaml";
    before = [ "podman-watchyourlan.service" ];
    requiredBy = [ "podman-watchyourlan.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      pkgs.coreutils
      pkgs.gnused
    ];
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
      shoutrrr_url: "gotify://gotify.${baseFacts.domainName}/__TOKEN__/?title=WatchYourLAN"
      theme: sand
      timeout: 60
      trim_hist: 48
      use_db: sqlite
      WYL_CONF
              sed -i "s/__TOKEN__/$TOKEN/" "$CONFIG"
            fi
    '';
  };

  virtualisation.oci-containers.containers.watchyourlan = {
    image = "ghcr.io/aceberg/watchyourlan:${wylTag}";
    volumes = [
      "${wylBase}:/data/WatchYourLAN"
    ];
    environment = {
      TZ = baseFacts.timeZone;
      IFACES = "ens18";
    };
    extraOptions = [
      "--network=host"
      "--cap-add=NET_ADMIN"
      "--cap-add=NET_RAW"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      watchyourlan = {
        rule = "Host(`watchyourlan.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "watchyourlan-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      "watchyourlan-outpost" = {
        rule = "Host(`watchyourlan.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."watchyourlan-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:8840"; } ];
  };

  ligma.dnsRecords."watchyourlan.${baseFacts.domainName}".value = hosts.ligma;
}
