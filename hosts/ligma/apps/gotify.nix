{ ... }:
let
  gotifyPort = 8096;
  gotifyBase = "/ligma/ligma/gotify";
  # renovate: datasource=docker depName=gotify/server
  gotifyTag  = "2";
in
{
  systemd.tmpfiles.rules = [
    "d '${gotifyBase}' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.gotify = {
    image       = "docker.io/gotify/server:${gotifyTag}";
    ports       = [ "127.0.0.1:${toString gotifyPort}:80" ];
    environment = { TZ = "Europe/Stockholm"; };
    volumes     = [ "${gotifyBase}:/app/data" ];
  };

  # ---------------------------------------------------------------------------
  # Traefik
  #
  # Three routers, explicit priorities:
  #   gotify-outpost (30)  — Authentik post-login callback, no middleware
  #   gotify-token   (10)  — requests with X-Gotify-Key header bypass Authentik
  #                          so push senders and API clients work without SSO
  #   gotify          (1)  — catch-all, Authentik gate for browser access
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      gotify-outpost = {
        rule        = "Host(`gotify.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority    = 30;
        entryPoints = [ "websecure" ];
        service     = "gotify-svc";
        tls.certResolver = "letsencrypt";
      };
      gotify-token = {
        rule        = "Host(`gotify.makifun.se`) && HeaderRegexp(`X-Gotify-Key`, `.+`)";
        priority    = 10;
        entryPoints = [ "websecure" ];
        service     = "gotify-svc";
        tls.certResolver = "letsencrypt";
      };
      gotify = {
        rule        = "Host(`gotify.makifun.se`)";
        priority    = 1;
        entryPoints = [ "websecure" ];
        service     = "gotify-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."gotify-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString gotifyPort}"; }
    ];
  };
}
