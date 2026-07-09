{ config, ... }:
let
  # renovate: datasource=docker depName=technitium/dns-server
  technitiumTag = "15.3.0";
  technitiumBase = "/ligma/ligma/technitium";
in
{
  systemd.tmpfiles.rules = [
    "d '${technitiumBase}' 0755 root root - -"
  ];

  sops.secrets.technitium-admin-password = {
    sopsFile = ../secrets.yaml;
  };

  # ---------------------------------------------------------------------------
  # Technitium DNS Server — primary LAN resolver.
  #
  # DNS_SERVER_ADMIN_PASSWORD_FILE is only read on first boot (no config.json
  # yet); UI password changes persist afterward in ${technitiumBase}.
  # Port 53 published on all interfaces; firewall below restricts source to
  # LAN/WG. Web console stays loopback-only, reached through Traefik.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.technitium = {
    image = "docker.io/technitium/dns-server:${technitiumTag}";
    ports = [
      "53:53/udp"
      "53:53/tcp"
      "127.0.0.1:5380:5380/tcp"
    ];
    environment = {
      DNS_SERVER_DOMAIN = "technitium.makifun.se";
      DNS_SERVER_ADMIN_PASSWORD_FILE = config.sops.secrets.technitium-admin-password.path;
    };
    volumes = [
      "${technitiumBase}:/etc/dns"
      "${config.sops.secrets.technitium-admin-password.path}:${config.sops.secrets.technitium-admin-password.path}:ro"
    ];
  };

  # ---------------------------------------------------------------------------
  # Firewall — DNS queries accepted from LAN + WireGuard clients only.
  # ---------------------------------------------------------------------------
  networking.firewall.extraInputRules = ''
    ip saddr { 10.10.10.0/24, 10.10.11.0/24 } udp dport 53 accept comment "Technitium DNS (LAN + WG)"
    ip saddr { 10.10.10.0/24, 10.10.11.0/24 } tcp dport 53 accept comment "Technitium DNS (LAN + WG)"
  '';

  # ---- Traefik ----------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      technitium = {
        rule = "Host(`technitium.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "technitium-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      technitium-outpost = {
        rule = "Host(`technitium.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."technitium-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:5380"; } ];
  };
}
