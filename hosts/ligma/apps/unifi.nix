{ pkgs, ... }:
let
  unifiPort = 8443;  # HTTPS web UI — self-signed cert, Traefik terminates TLS externally
in
{
  # ---------------------------------------------------------------------------
  # Data directory on zstorage
  #
  # services.unifi hardcodes /var/lib/unifi and does not accept a custom path
  # (the dataDir option asserts it must equal /var/lib/unifi/data).
  # Bind-mount the zstorage path at the location the module expects so data
  # survives reboots on the ephemeral root tmpfs.
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/unifi' 0700 unifi unifi - -"
  ];

  fileSystems."/var/lib/unifi" = {
    device        = "/ligma/ligma/unifi";
    options       = [ "bind" ];
    neededForBoot = false;
  };

  # ---------------------------------------------------------------------------
  # UniFi Network Application
  # ---------------------------------------------------------------------------
  services.unifi = {
    enable         = true;
    openFirewall   = false;  # managed manually below
    unifiPackage   = pkgs.unifi8;
    mongodbPackage = pkgs.mongodb-ce;
  };

  # ---------------------------------------------------------------------------
  # Firewall
  #
  # 8080/tcp  — device inform (APs + switches contact the controller here)
  # 3478/udp  — STUN (used by UniFi devices for NAT traversal)
  # 10001/udp — L2 AP discovery
  #
  # 8443 is intentionally not opened; Traefik proxies the web UI locally.
  # ---------------------------------------------------------------------------
  networking.firewall.extraInputRules = ''
    tcp dport 8080 ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept comment "UniFi device inform"
    udp dport { 3478, 10001 } ip saddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16 } accept comment "UniFi STUN + discovery"
  '';

  # ---------------------------------------------------------------------------
  # Traefik
  #
  # UniFi's web UI serves HTTPS with a self-signed cert on localhost:8443.
  # serversTransport skips TLS verification for the backend connection only;
  # the public-facing TLS (unifi.makifun.se) is fully valid via Let's Encrypt.
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
      # Routes the Authentik post-login callback back to the embedded outpost.
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
