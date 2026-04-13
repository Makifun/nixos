{ pkgs, lib, ... }:
let
  unifiPort = 8443;
  unifiBase = "/ligma/ligma/unifi";
in
{
  systemd.tmpfiles.rules = [
    "d '${unifiBase}/config' 0755 root root - -"
    "d '${unifiBase}/db'     0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Containers
  #
  # Podman network DNS (hostname resolution between named containers) was
  # unreliable on this host. Replaced with a simpler approach:
  #   - unifi-db publishes MongoDB to 127.0.0.1:27017 (host loopback only)
  #   - unifi connects via host.containers.internal — a hostname Podman
  #     injects into every container's /etc/hosts pointing at the host
  # No custom network or DNS needed.
  #
  # MongoDB auth is not enabled; mongo:7 without --auth accepts any credentials
  # in the connection URI. The loopback-only port publish ensures it is not
  # reachable from outside the host.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = {

    unifi-db = {
      image   = "docker.io/mongo:7";
      volumes = [ "${unifiBase}/db:/data/db" ];
      ports   = [ "127.0.0.1:27017:27017" ];
    };

    unifi = {
      image     = "lscr.io/linuxserver/unifi-network-application:latest";
      dependsOn = [ "unifi-db" ];
      environment = {
        PUID         = "1000";
        PGID         = "1000";
        TZ           = "Europe/Stockholm";
        MONGO_USER   = "unifi";
        MONGO_PASS   = "unifi";
        MONGO_HOST   = "host.containers.internal";
        MONGO_PORT   = "27017";
        MONGO_DBNAME = "unifi";
        MEM_LIMIT    = "1024";
        MEM_STARTUP  = "1024";
      };
      volumes = [ "${unifiBase}/config:/config" ];
      ports   = [
        "127.0.0.1:${toString unifiPort}:${toString unifiPort}"  # web UI → Traefik only
        "0.0.0.0:8080:8080"        # device inform
        "0.0.0.0:3478:3478/udp"    # STUN
        "0.0.0.0:10001:10001/udp"  # AP discovery
      ];
    };
  };

  # Wait until MongoDB is actually accepting connections before starting UniFi.
  # Uses bash /dev/tcp — no extra packages needed.
  systemd.services.podman-unifi.preStart = lib.mkAfter ''
    until (echo > /dev/tcp/127.0.0.1/27017) 2>/dev/null; do
      echo "Waiting for MongoDB on 127.0.0.1:27017..."
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
