{ ... }:
let
  apprisePort = 8097;
  appriseBase = "/ligma/ligma/apprise";
  # renovate: datasource=docker depName=linuxserver/apprise-api registryUrl=https://lscr.io
  appriseTag  = "1.3.3";
in
{
  systemd.tmpfiles.rules = [
    "d '${appriseBase}/config'      0755 root root - -"
    "d '${appriseBase}/attachments' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.apprise = {
    image       = "lscr.io/linuxserver/apprise-api:${appriseTag}";
    ports       = [ "127.0.0.1:${toString apprisePort}:8000" ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ   = "Europe/Stockholm";
    };
    volumes = [
      "${appriseBase}/config:/config"
      "${appriseBase}/attachments:/attachments"
    ];
  };

  # ---------------------------------------------------------------------------
  # Traefik
  #
  # Three routers, explicit priorities:
  #   apprise-outpost (30) — Authentik post-login callback, no middleware
  #   apprise-api     (10) — /notify paths bypass Authentik so external
  #                          services can send notifications without SSO
  #   apprise          (1) — catch-all, Authentik gate for browser access
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      apprise-outpost = {
        rule        = "Host(`apprise.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority    = 30;
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      apprise-api = {
        rule        = "Host(`apprise.makifun.se`) && PathPrefix(`/notify`)";
        priority    = 10;
        entryPoints = [ "websecure" ];
        service     = "apprise-svc";
        tls.certResolver = "letsencrypt";
      };
      apprise = {
        rule        = "Host(`apprise.makifun.se`)";
        priority    = 1;
        entryPoints = [ "websecure" ];
        service     = "apprise-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."apprise-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString apprisePort}"; }
    ];
  };
}
