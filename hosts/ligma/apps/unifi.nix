{ pkgs, lib, ... }:
let
  unifiPort = 8443;
  unifiBase = "/ligma/ligma/unifi";

  # Internal MongoDB credentials — isolated container network, never exposed externally.
  mongoUser = "unifi";
  mongoPass = "unifi_internal";

  # Init script runs once when MongoDB data dir is empty (fresh install).
  # Creates the two databases the UniFi controller expects.
  mongoInitScript = pkgs.writeText "unifi-mongo-init.js" ''
    db.getSiblingDB("unifi").createUser({
      user: "${mongoUser}", pwd: "${mongoPass}",
      roles: [{ role: "dbOwner", db: "unifi" }]
    });
    db.getSiblingDB("unifi_stat").createUser({
      user: "${mongoUser}", pwd: "${mongoPass}",
      roles: [{ role: "dbOwner", db: "unifi_stat" }]
    });
  '';
in
{
  systemd.tmpfiles.rules = [
    "d '${unifiBase}/config' 0755 root root - -"
    "d '${unifiBase}/db'     0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Isolated Podman network shared by unifi-db and unifi containers.
  # ---------------------------------------------------------------------------
  systemd.services.podman-create-unifi-network = {
    description    = "Create unifi_network podman network";
    before         = [ "podman-unifi-db.service" "podman-unifi.service" ];
    requiredBy     = [ "podman-unifi-db.service" "podman-unifi.service" ];
    serviceConfig  = { Type = "oneshot"; RemainAfterExit = true; };
    path           = [ pkgs.podman ];
    script         = "podman network exists unifi_network || podman network create unifi_network";
  };

  # ---------------------------------------------------------------------------
  # Containers
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = {

    unifi-db = {
      image   = "docker.io/mongo:7";
      volumes = [
        "${mongoInitScript}:/docker-entrypoint-initdb.d/init.js:ro"
        "${unifiBase}/db:/data/db"
      ];
      extraOptions = [ "--network=unifi_network" "--hostname=unifi-db" ];
    };

    unifi = {
      image     = "lscr.io/linuxserver/unifi-network-application:latest";
      dependsOn = [ "unifi-db" ];
      environment = {
        PUID         = "1000";
        PGID         = "1000";
        TZ           = "Europe/Stockholm";
        MONGO_USER   = mongoUser;
        MONGO_PASS   = mongoPass;
        MONGO_HOST   = "unifi-db";
        MONGO_PORT   = "27017";
        MONGO_DBNAME = "unifi";
        MEM_LIMIT    = "1024";
        MEM_STARTUP  = "1024";
      };
      volumes = [ "${unifiBase}/config:/config" ];
      ports   = [
        "127.0.0.1:${toString unifiPort}:${toString unifiPort}"  # web UI → Traefik only
        "0.0.0.0:8080:8080"          # device inform
        "0.0.0.0:3478:3478/udp"      # STUN
        "0.0.0.0:10001:10001/udp"    # AP discovery
      ];
      extraOptions = [ "--network=unifi_network" ];
    };
  };

  # Wait for unifi-db to be running before starting UniFi.
  # Podman DNS registers the container name only after the container is running;
  # UniFi's Java process starts fast enough to race ahead of that registration.
  systemd.services.podman-unifi.preStart = lib.mkAfter ''
    until ${pkgs.podman}/bin/podman container inspect unifi-db \
        --format '{{.State.Running}}' 2>/dev/null | grep -q true; do
      echo "Waiting for unifi-db to be running..."
      sleep 2
    done
  '';

  # ---------------------------------------------------------------------------
  # Firewall
  # ---------------------------------------------------------------------------
  networking.firewall.extraInputRules = ''
    tcp dport 8080 ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept comment "UniFi device inform"
    udp dport { 3478, 10001 } ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept comment "UniFi STUN + discovery"
  '';

  # ---------------------------------------------------------------------------
  # Traefik
  #
  # The linuxserver image serves HTTPS with a self-signed cert on 8443.
  # serversTransport skips verification for the local backend only.
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      unifi = {
        rule        = "Host(`unifi.makifun.se`)";
        entryPoints = [ "websecure" ];
        service     = "unifi-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      "unifi-outpost" = {
        rule        = "Host(`unifi.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."unifi-svc".loadBalancer = {
      servers          = [{ url = "https://127.0.0.1:${toString unifiPort}"; }];
      serversTransport = "unifi-transport";
    };
    serversTransports."unifi-transport".insecureSkipVerify = true;
  };
}
