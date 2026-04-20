{ config, ... }:
let
  backrestPort = 9898;
  backrestBase = "/ligma/ligma/backrest";
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.12.1";
in
{
  # ---------------------------------------------------------------------------
  # Secrets
  # Add to secrets.yaml:
  #   backrest-restic-password: "<strong random password>"
  #   backrest-repo-uri:        "s3:s3.amazonaws.com/<bucket>/<prefix>"
  #   backrest-aws-access-key-id:     "<key id>"
  #   backrest-aws-secret-access-key: "<secret key>"
  #
  # Reference these in backrest UI repo config using Go template syntax:
  #   Password:              {{ .Env.BACKREST_RESTIC_PASSWORD }}
  #   Env var (key id):      AWS_ACCESS_KEY_ID={{ .Env.AWS_ACCESS_KEY_ID }}
  #   Env var (secret key):  AWS_SECRET_ACCESS_KEY={{ .Env.AWS_SECRET_ACCESS_KEY }}
  #   URI:                   {{ .Env.BACKREST_REPO_URI }}
  # ---------------------------------------------------------------------------

  sops.secrets = {
    backrest-restic-password    = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-repo-uri           = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-aws-access-key-id  = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-aws-secret-access-key = { format = "yaml"; sopsFile = ../secrets.yaml; };
  };

  sops.templates."backrest-env" = {
    content = ''
      BACKREST_RESTIC_PASSWORD=${config.sops.placeholder.backrest-restic-password}
      BACKREST_REPO_URI=${config.sops.placeholder.backrest-repo-uri}
      AWS_ACCESS_KEY_ID=${config.sops.placeholder.backrest-aws-access-key-id}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backrest-aws-secret-access-key}
    '';
  };

  systemd.tmpfiles.rules = [
    "d '${backrestBase}/data'   0750 root root - -"
    "d '${backrestBase}/config' 0750 root root - -"
    "d '${backrestBase}/cache'  0750 root root - -"
  ];

  virtualisation.oci-containers.containers.backrest = {
    image            = "ghcr.io/garethgeorge/backrest:${backrestTag}";
    ports            = [ "127.0.0.1:${toString backrestPort}:9898" ];
    environmentFiles = [ config.sops.templates."backrest-env".path ];
    volumes = [
      "${backrestBase}/data:/data"
      "${backrestBase}/config:/config"
      "${backrestBase}/cache:/cache"
      "/ligma:/ligma:ro"
    ];
  };

  # ---------------------------------------------------------------------------
  # Traefik — Authentik SSO gate
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      backrest-outpost = {
        rule        = "Host(`backrest.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority    = 30;
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      backrest = {
        rule        = "Host(`backrest.makifun.se`)";
        priority    = 1;
        entryPoints = [ "websecure" ];
        service     = "backrest-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."backrest-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString backrestPort}"; }
    ];
  };
}
