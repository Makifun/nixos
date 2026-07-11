{ ... }:
let
  technitiumIp = "10.10.10.3";
in
{
  # Technitium DNS Server runs as an LXC on Proxmox — not managed here.
  # This file only adds Traefik routes.
  #
  # technitium.makifun.se → WebGUI (https://10.10.10.3:53443, self-signed cert)
  #   Protected by Authentik forwardAuth + OIDC (configured in authentik/technitium.tf).
  #
  # doh.makifun.se → DoH endpoint (http://10.10.10.3/dns-query)
  #   No auth — DoH clients must be able to reach this without SSO.
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      technitium-outpost = {
        rule = "Host(`technitium.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority = 30;
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      technitium = {
        rule = "Host(`technitium.makifun.se`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "technitium-svc";
        middlewares = [ "authentik" ];
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
}
