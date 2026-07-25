{ config, ... }:
let
  gotifyPort = 8096;
  gotifyBase = "/ligma/ligma/gotify";
  # renovate: datasource=docker depName=gotify/server
  gotifyTag = "3.0.0";
in
{
  systemd.tmpfiles.rules = [
    "d '${gotifyBase}' 0755 root root - -"
  ];

  sops.secrets.gotify-oidc-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Write OIDC client secret to a runtime env file so the container picks it up.
  systemd.services.gotify-env-setup = {
    description = "Write Gotify runtime env file from SOPS secrets";
    before = [ "podman-gotify.service" ];
    requiredBy = [ "podman-gotify.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      printf 'GOTIFY_OIDC_CLIENTSECRET=%s\n' \
        "$(tr -d '\n' < ${config.sops.secrets.gotify-oidc-secret.path})" \
        > /run/gotify-oidc.env
      chmod 400 /run/gotify-oidc.env
    '';
  };

  # Wait for Authentik server before starting — Gotify does OIDC discovery at
  # startup and fails with 503 if Authentik is still initialising.
  systemd.services.podman-gotify = {
    after = [ "podman-authentik-server.service" ];
    wants = [ "podman-authentik-server.service" ];
    serviceConfig = {
      RestartSec = "30s";
      StartLimitBurst = 10;
    };
  };

  virtualisation.oci-containers.containers.gotify = {
    image = "docker.io/gotify/server:${gotifyTag}";
    ports = [ "127.0.0.1:${toString gotifyPort}:80" ];
    environment = {
      TZ = "Europe/Stockholm";
      # Traefik is on 127.0.0.1 — trust it as reverse proxy for real client IPs.
      GOTIFY_SERVER_TRUSTEDPROXIES = "127.0.0.1";
      GOTIFY_OIDC_ENABLED = "true";
      GOTIFY_OIDC_ISSUER = "https://auth.makifun.se/application/o/gotify/";
      GOTIFY_OIDC_CLIENTID = "gotify";
      GOTIFY_OIDC_REDIRECTURL = "https://gotify.makifun.se/auth/oidc/callback";
      # Link OIDC logins to existing local users with matching usernames.
      GOTIFY_OIDC_LINK_BY_USERNAME = "true";
    };
    environmentFiles = [ "/run/gotify-oidc.env" ];
    volumes = [ "${gotifyBase}:/app/data" ];
  };

  # ---------------------------------------------------------------------------
  # Traefik
  #
  # Two routers (Gotify v3 handles auth natively via OIDC — no Authentik proxy):
  #   gotify-token (10) — X-Gotify-Key header bypasses OIDC for push senders
  #   gotify        (1) — catch-all, no middleware (Gotify does OIDC itself)
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      gotify-token = {
        rule = "Host(`gotify.makifun.se`) && HeaderRegexp(`X-Gotify-Key`, `.+`)";
        priority = 10;
        entryPoints = [ "websecure" ];
        service = "gotify-svc";
        tls.certResolver = "letsencrypt";
      };
      gotify = {
        rule = "Host(`gotify.makifun.se`)";
        priority = 1;
        entryPoints = [ "websecure" ];
        service = "gotify-svc";
        tls.certResolver = "letsencrypt";
      };
    };
    services."gotify-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString gotifyPort}"; }
    ];
  };

  ligma.dnsRecords."gotify.makifun.se".value = "10.10.10.13";
}
