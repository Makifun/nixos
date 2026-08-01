{
  config,
  pkgs,
  lib,
  baseFacts,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  gotifyPort = 8096;
  gotifyBase = "/${hostname}/${hostname}/gotify";
  # renovate: datasource=docker depName=gotify/server
  gotifyTag = "3.0.0";
  waitForAuthentik = pkgs.writeShellScript "gotify-wait-authentik" ''
    until ${pkgs.curl}/bin/curl -sf --max-time 10 \
      https://auth.${baseFacts.domainName}/application/o/gotify/.well-known/openid-configuration \
      > /dev/null 2>&1; do
      sleep 5
    done
  '';
in
{
  sops.secrets.gotify-oidc-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '${gotifyBase}' 0755 root root - -"
  ];

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

  # Block Gotify start until Authentik's OIDC discovery endpoint returns 200.
  # `after` alone is not enough — it only waits for the container to start,
  # not for Authentik to finish initialising internally.
  systemd.services.podman-gotify = {
    after = [ "podman-authentik-server.service" ];
    wants = [ "podman-authentik-server.service" ];
    serviceConfig = {
      ExecStartPre = "${waitForAuthentik}";
      TimeoutStartSec = lib.mkForce 300;
      RestartSec = "30s";
      StartLimitIntervalSec = "0";
    };
  };

  virtualisation.oci-containers.containers.gotify = {
    image = "docker.io/gotify/server:${gotifyTag}";
    ports = [ "127.0.0.1:${toString gotifyPort}:80" ];
    environment = {
      TZ = "${baseFacts.timeZone}";
      GOTIFY_SERVER_TRUSTEDPROXIES = "127.0.0.1";
      GOTIFY_OIDC_ENABLED = "true";
      GOTIFY_OIDC_ISSUER = "https://auth.${baseFacts.domainName}/application/o/gotify/";
      GOTIFY_OIDC_CLIENTID = "gotify";
      GOTIFY_OIDC_REDIRECTURL = "https://gotify.${baseFacts.domainName}/auth/oidc/callback";
      GOTIFY_OIDC_LINK_BY_USERNAME = "true";
    };
    environmentFiles = [ "/run/gotify-oidc.env" ];
    volumes = [ "${gotifyBase}:/app/data" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      gotify-token = {
        rule = "Host(`gotify.${baseFacts.domainName}`) && HeaderRegexp(`X-Gotify-Key`, `.+`)";
        priority = 10;
        entryPoints = [ "websecure" ];
        service = "gotify-svc";
        tls.certResolver = "letsencrypt";
      };
      gotify = {
        rule = "Host(`gotify.${baseFacts.domainName}`)";
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

  ligma.dnsRecords."gotify.${baseFacts.domainName}".value = hosts.ligma;
}
