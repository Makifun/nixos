{ pkgs, lib, ... }:
let
  unifiPort = 8443;
  unifiBase = "/ligma/ligma/unifi";
  # renovate: datasource=docker depName=mongo versioning=semver
  mongoTag  = "8.2.6";
  # renovate: datasource=docker depName=linuxserver/unifi-network-application registryUrl=https://lscr.io
  unifiTag  = "10.3.55";
in
{
  systemd.tmpfiles.rules = [
    "d '${unifiBase}/config' 0755 root root - -"
    "d '${unifiBase}/db'     0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Isolated Podman network for unifi + unifi-db.
  # ---------------------------------------------------------------------------
  systemd.services.podman-create-unifi-network = {
    description    = "Create unifi_network podman network";
    before         = [ "podman-unifi-db.service" "podman-unifi.service" ];
    requiredBy     = [ "podman-unifi-db.service" "podman-unifi.service" ];
    serviceConfig  = { Type = "oneshot"; RemainAfterExit = true; };
    path           = [ pkgs.podman ];
    script         = "podman network exists unifi_network || podman network create --subnet 10.89.0.0/24 unifi_network";
  };

  # ---------------------------------------------------------------------------
  # Containers
  #
  # Podman network DNS was unreliable for custom networks on this host.
  # Workaround: point both containers at the default Podman gateway (10.88.0.1)
  # as the DNS server — aardvark-dns there resolves names across all networks.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = {

    unifi-db = {
      image   = "docker.io/amd64/mongo:${mongoTag}";
      volumes = [ "${unifiBase}/db:/data/db" ];
      extraOptions = [ "--network=unifi_network" ];
    };

    unifi = {
      image     = "lscr.io/linuxserver/unifi-network-application:${unifiTag}";
      dependsOn = [ "unifi-db" ];
      environment = {
        PUID         = "1000";
        PGID         = "1000";
        TZ           = "Europe/Stockholm";
        MONGO_USER   = "unifi";
        MONGO_PASS   = "unifi";
        MONGO_HOST   = "unifi-db";
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
      extraOptions = [ "--network=unifi_network" ];
    };
  };

  # Wait until unifi-db is running and registered in DNS before starting UniFi.
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
    tcp dport 8080 ip saddr 10.10.10.0/24 accept comment "UniFi device inform"
    udp dport { 3478, 10001 } ip saddr 10.10.10.0/24 accept comment "UniFi STUN + discovery"
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
