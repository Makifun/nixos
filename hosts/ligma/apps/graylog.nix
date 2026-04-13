{ config, lib, pkgs, ... }:
let
  glBase = "/ligma/ligma/graylog";
  glPort = 9099;  # 9000 is taken by the Authentik embedded outpost

  # Script that writes /run/graylog/env with SOPS secrets.
  # Embedded directly in podman-datanode's preStart so it runs on every
  # start including systemd auto-restarts (After/Requires only apply to
  # initial starts, not restart loops).
  writeEnvFile = ''
    mkdir -p /run/graylog
    chmod 700 /run/graylog
    secret=$(tr -d '\n' < ${config.sops.secrets.graylog-password-secret.path})
    sha2=$(tr -d '\n' < ${config.sops.secrets.graylog-root-password-sha2.path})
    {
      printf 'GRAYLOG_PASSWORD_SECRET=%s\n'              "$secret"
      printf 'GRAYLOG_ROOT_PASSWORD_SHA2=%s\n'           "$sha2"
      printf 'GRAYLOG_DATANODE_PASSWORD_SECRET=%s\n'     "$secret"
      printf 'GRAYLOG_DATANODE_ROOT_PASSWORD_SHA2=%s\n'  "$sha2"
    } > /run/graylog/env
    chmod 400 /run/graylog/env
  '';
in
{
  # ---------------------------------------------------------------------------
  # Secrets
  # Generate and add to secrets.yaml:
  #   graylog-password-secret: "<output of: pwgen -N1 -s 96>"
  #   graylog-root-password-sha2: "<output of: echo -n 'yourpassword' | sha256sum | cut -d' ' -f1>"
  # ---------------------------------------------------------------------------
  sops.secrets.graylog-password-secret = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.graylog-root-password-sha2 = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/mongodb'  0755 root root - -"
    "d '/ligma/ligma/datanode' 0755 root root - -"
    "d '${glBase}'            0755 root root - -"
    "d '${glBase}/journal'    0750 1100 1100 - -"  # graylog runs as UID 1100 in the container
    "d '${glBase}/data'       0750 1100 1100 - -"
  ];

  # ---------------------------------------------------------------------------
  # Create the isolated podman network shared by all three containers.
  # ---------------------------------------------------------------------------
  systemd.services.podman-create-graylog-network = {
    description    = "Create graylog_network podman network";
    before         = [ "podman-mongodb.service" "podman-datanode.service" "podman-graylog.service" ];
    requiredBy     = [ "podman-mongodb.service" "podman-datanode.service" "podman-graylog.service" ];
    serviceConfig  = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path   = [ pkgs.podman ];
    script = "podman network exists graylog_network || podman network create graylog_network";
  };

  # ---------------------------------------------------------------------------
  # Write env file in each container's preStart independently.
  # Both services write the same content so whichever starts first wins,
  # and restarts are always self-sufficient regardless of ordering.
  # ---------------------------------------------------------------------------
  systemd.services.podman-datanode.preStart = lib.mkBefore writeEnvFile;
  systemd.services.podman-graylog.preStart  = lib.mkBefore writeEnvFile;

  # ---------------------------------------------------------------------------
  # Containers
  # MongoDB and Datanode are only reachable within graylog_network.
  # Graylog publishes its HTTP port to localhost for Traefik.
  # Inter-container hostnames resolved via podman DNS: mongodb, datanode, graylog.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = {

    mongodb = {
      image        = "docker.io/mongo:8";
      volumes      = [ "/ligma/ligma/mongodb:/data/db" ];
      extraOptions = [ "--network=graylog_network" ];
    };

    datanode = {
      image            = "docker.io/graylog/graylog-datanode:7.0";
      environmentFiles = [ "/run/graylog/env" ];
      environment = {
        GRAYLOG_DATANODE_MONGODB_URI   = "mongodb://mongodb/graylog";
        GRAYLOG_DATANODE_NODE_NAME     = "datanode";
        GRAYLOG_DATANODE_ROOT_USERNAME = "admin";
        GRAYLOG_DATANODE_OPENSEARCH_HEAP = "2g";
      };
      volumes      = [ "/ligma/ligma/datanode:/var/lib/graylog-datanode" ];
      extraOptions = [ "--network=graylog_network" "--hostname=datanode" ];
    };

    graylog = {
      image            = "docker.io/graylog/graylog:7.0";
      dependsOn        = [ "mongodb" "datanode" ];
      environmentFiles = [ "/run/graylog/env" ];
      environment = {
        GRAYLOG_MONGODB_URI       = "mongodb://mongodb/graylog";
        GRAYLOG_HTTP_BIND_ADDRESS = "0.0.0.0:${toString glPort}";
        GRAYLOG_HTTP_EXTERNAL_URI = "https://graylog.makifun.se/";
        TZ                        = "Europe/Stockholm";  # JVM/OS timezone
        GRAYLOG_ROOT_TIMEZONE     = "Europe/Stockholm";  # Graylog root_timezone config
        # Trust the username header from Traefik on the host.
        # Traefik reaches the container via the Podman host gateway; covering
        # loopback + RFC-1918 catches all possible Podman gateway IPs.
        # Maps to trusted_proxies in server.conf.
        GRAYLOG_TRUSTED_PROXIES = "127.0.0.1/32,172.16.0.0/12,10.0.0.0/8";
      };
      ports   = [
        "127.0.0.1:${toString glPort}:${toString glPort}"
        "0.0.0.0:5140:5140/udp"  # OPNsense syslog (filterlog)
        "0.0.0.0:5141:5141/udp"    # UniFi syslog (UniFi container reaches host via Podman gateway)
      ];
      volumes = [
        "${glBase}/journal:/usr/share/graylog/data/journal"
        "${glBase}/data:/usr/share/graylog/data/data"
      ];
      extraOptions = [ "--network=graylog_network" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  networking.firewall.extraInputRules = ''
    udp dport 5140 ip saddr 10.10.10.0/24 accept comment "Graylog syslog UDP (OPNsense)"
    udp dport 5141 ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept comment "Graylog syslog UDP (UniFi container via Podman gateway)"
  '';

  # ---------------------------------------------------------------------------
  # Traefik
  # Three routers, explicit priorities to avoid ambiguity:
  #
  #   graylog-outpost (30)   — Authentik post-login callback, no middleware
  #   graylog-basic-auth (10) — requests with Authorization: Basic bypass
  #                             Authentik so Terraform API tokens work;
  #                             Graylog validates the credential itself
  #   graylog (1)            — catch-all, Authentik gate + header injection
  #                             for browser / SSO flow
  #
  # The SPA's initial auth check (GET /api/system/session, no Authorization
  # header) hits the catch-all, Authentik injects X-authentik-username, and
  # Graylog auto-logs in via Trusted Header Authentication.
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      graylog-outpost = {
        rule        = "Host(`graylog.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority    = 30;
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      graylog-basic-auth = {
        rule        = "Host(`graylog.makifun.se`) && HeaderRegexp(`Authorization`, `^Basic .+`)";
        priority    = 10;
        entryPoints = [ "websecure" ];
        service     = "graylog-svc";
        tls.certResolver = "letsencrypt";
      };
      graylog = {
        rule        = "Host(`graylog.makifun.se`)";
        priority    = 1;
        entryPoints = [ "websecure" ];
        service     = "graylog-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services.graylog-svc.loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString glPort}"; }
    ];
  };
}
