{ pkgs, lib, ... }:
let
  unifiPort = 8443;
  unifiBase = "/ligma/ligma/unifi";
  # renovate: datasource=docker depName=mongo versioning=semver
  mongoTag = "8.2.6";
  # renovate: datasource=docker depName=linuxserver/unifi-network-application registryUrl=https://lscr.io
  unifiTag = "10.4.57";

  # UniFi sends CEF embedded in BSD syslog WITHOUT a <priority> field.
  # Alloy's loki.source.syslog rejects any message not starting with '<'.
  # Workaround: a tiny Python service receives raw UDP datagrams and appends
  # each line to a file that Alloy's loki.source.file tails into Loki.
  #
  # Two senders observed via tcpdump:
  #   10.10.10.2  (ens18)   — UniFi APs send their own syslog directly
  #   10.89.0.9   (podman2) — UniFi Network Application container
  unifiSyslogRecv = pkgs.writeScript "unifi-syslog-recv" ''
    #!${pkgs.python3}/bin/python3
    import socket, os
    LOG = "/var/log/unifi/events.log"
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", 5141))
    with open(LOG, "a", buffering=1) as f:
        while True:
            data, _ = sock.recvfrom(65536)
            f.write(data.decode("utf-8", errors="replace").rstrip("\n") + "\n")
  '';

in
{
  systemd.tmpfiles.rules = [
    "d '${unifiBase}/config' 0755 root root - -"
    "d '${unifiBase}/db'     0755 root root - -"
    "d '/var/log/unifi'      0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Isolated Podman network for unifi + unifi-db.
  # ---------------------------------------------------------------------------
  systemd.services.podman-create-unifi-network = {
    description = "Create unifi_network podman network";
    before = [
      "podman-unifi-db.service"
      "podman-unifi.service"
    ];
    requiredBy = [
      "podman-unifi-db.service"
      "podman-unifi.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.podman ];
    script = "podman network exists unifi_network || podman network create --subnet 10.89.0.0/24 unifi_network";
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
      image = "docker.io/amd64/mongo:${mongoTag}";
      volumes = [ "${unifiBase}/db:/data/db" ];
      extraOptions = [ "--network=unifi_network" ];
    };

    unifi = {
      image = "lscr.io/linuxserver/unifi-network-application:${unifiTag}";
      dependsOn = [ "unifi-db" ];
      environment = {
        PUID = "1000";
        PGID = "1000";
        TZ = "Europe/Stockholm";
        MONGO_USER = "unifi";
        MONGO_PASS = "unifi";
        MONGO_HOST = "unifi-db";
        MONGO_PORT = "27017";
        MONGO_DBNAME = "unifi";
        MEM_LIMIT = "1024";
        MEM_STARTUP = "1024";
      };
      volumes = [ "${unifiBase}/config:/config" ];
      ports = [
        "127.0.0.1:${toString unifiPort}:${toString unifiPort}" # web UI → Traefik only
        "0.0.0.0:8080:8080" # device inform
        "0.0.0.0:3478:3478/udp" # STUN
        "0.0.0.0:10001:10001/udp" # AP discovery
      ];
      extraOptions = [ "--network=unifi_network" ];
    };

    # Alloy needs to read /var/log/unifi/events.log.
    alloy.volumes = [ "/var/log/unifi:/var/log/unifi:ro" ];
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
  # UniFi syslog receiver
  # Receives raw UDP datagrams on port 5141 and appends them as lines to
  # /var/log/unifi/events.log which Alloy tails into Loki.
  # ---------------------------------------------------------------------------
  systemd.services.unifi-syslog = {
    description = "UniFi syslog UDP receiver → file";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = unifiSyslogRecv;
      Restart = "always";
    };
  };

  # ---------------------------------------------------------------------------
  # Alloy: tail /var/log/unifi/events.log → Loki
  # Appended to alloy/config.alloy (types.lines merges across modules).
  # loki.write.loki is defined in common/alloy.nix.
  # ---------------------------------------------------------------------------
  environment.etc."alloy/config.alloy".text = ''
    // ── UniFi syslog → Loki ───────────────────────────────────────────────────
    // UniFi sends CEF in BSD syslog without <priority>; loki.source.syslog
    // rejects it. unifi-syslog.service writes raw UDP datagrams to a file;
    // Alloy tails the file.

    loki.source.file "unifi" {
      targets = [{
        __path__ = "/var/log/unifi/events.log",
        job      = "ligma-unifi",
        host     = "ligma",
      }]
      forward_to = [loki.write.loki.receiver]
    }
  '';

  # ---------------------------------------------------------------------------
  # Firewall
  # Traffic arrives from two sources (both observed via tcpdump):
  #   10.10.10.0/24  — UniFi APs on LAN send syslog directly
  #   podman*        — UniFi container (already trusted by common/alloy.nix rule)
  # ---------------------------------------------------------------------------
  networking.firewall.extraInputRules = ''
    tcp dport 8080 ip saddr 10.10.10.0/24 accept comment "UniFi device inform"
    udp dport { 3478, 10001 } ip saddr 10.10.10.0/24 accept comment "UniFi STUN + discovery"
    udp dport 5141 ip saddr 10.10.10.0/24 accept comment "UniFi syslog (APs + controller)"
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
        rule = "Host(`unifi.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "unifi-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      "unifi-outpost" = {
        rule = "Host(`unifi.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."unifi-svc".loadBalancer = {
      servers = [ { url = "https://127.0.0.1:${toString unifiPort}"; } ];
      serversTransport = "unifi-transport";
    };
    serversTransports."unifi-transport".insecureSkipVerify = true;
  };

  ligma.dnsRecords."unifi.makifun.se".value = "10.10.10.13";
}
