{ config, pkgs, ... }:
let
  backrestPort = 9898;
  backrestBase = "/ligma/ligma/backrest";
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.12.1";

  configJson = pkgs.writeText "backrest-config.json" (builtins.toJSON {
    version = 4;
    modno = 1;
    instance = "ligma";
    auth.disabled = true;
    repos = [
      {
        id = "ligma-s3";
        guid = "7eef850cc715baa31782fffbe5a5f3e62529481760e12e7817e65ebc34e06184";
        uri = "{{ .Env.BACKREST_REPO_URI }}";
        password = "{{ .Env.BACKREST_RESTIC_PASSWORD }}";
        env = [
          "AWS_ACCESS_KEY_ID={{ .Env.AWS_ACCESS_KEY_ID }}"
          "AWS_SECRET_ACCESS_KEY={{ .Env.AWS_SECRET_ACCESS_KEY }}"
        ];
        prunePolicy.schedule.cron = "0 5 * * *";
      }
    ];
    plans = [
      {
        id = "ligma-daily";
        repo = "ligma-s3";
        paths = [ "/ligma" ];
        schedule.cron = "0 4 * * *";
        retention.policyTimeBucketed = {
          daily = 30;
          weekly = 8;
          monthly = 12;
        };
      }
    ];
  });
in
{
  sops.secrets = {
    backrest-restic-password       = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-repo-uri              = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-aws-access-key-id     = { format = "yaml"; sopsFile = ../secrets.yaml; };
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

  # Write config.json on first start only — backrest may modify it via the UI thereafter.
  systemd.services.backrest-config-init = {
    description = "Initialize backrest config.json";
    wantedBy    = [ "podman-backrest.service" ];
    before      = [ "podman-backrest.service" ];
    after       = [ "local-fs.target" ];
    serviceConfig = {
      Type              = "oneshot";
      RemainAfterExit   = true;
    };
    script = ''
      dest="${backrestBase}/config/config.json"
      if [ ! -f "$dest" ]; then
        cp ${configJson} "$dest"
        chmod 640 "$dest"
      fi
    '';
  };

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
