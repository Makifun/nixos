{ ... }:
let
  technitiumIp = "10.10.10.3";
in
{
  # Technitium DNS Server runs as an LXC on Proxmox — not managed here.
  # This file only adds Traefik routes.
  #
  # technitium.makifun.se → WebGUI (https://10.10.10.3:53443, self-signed cert)
  #   No Authentik forwardAuth — Technitium handles auth via its own OIDC login
  #   (configured in authentik/technitium.tf). Direct proxy, like Jellyfin.
  #
  # doh.makifun.se → DoH endpoint (http://10.10.10.3/dns-query)
  #   No auth — DoH clients must reach this unauthenticated.
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      technitium = {
        rule = "Host(`technitium.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "technitium-svc";
        tls.certResolver = "letsencrypt";
      };
      doh = {
        rule = "Host(`doh.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "doh-svc";
        tls.certResolver = "letsencrypt";
      };
    };
    services = {
      technitium-svc.loadBalancer = {
        servers = [ { url = "https://${technitiumIp}:53443"; } ];
        serversTransport = "technitium-transport";
      };
      doh-svc.loadBalancer.servers = [ { url = "http://${technitiumIp}"; } ];
    };
    serversTransports."technitium-transport".insecureSkipVerify = true;
  };

  ligma.dnsRecords."technitium.makifun.se".value = "10.10.10.13";
  ligma.dnsRecords."doh.makifun.se".value = "10.10.10.13";
}
