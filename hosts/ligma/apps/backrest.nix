{ config, lib, ... }:
let
  backrestPort = 9898;
  backrestBase = "/ligma/ligma/backrest";
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.12.1";
in
{
  sops.secrets = {
    backrest-restic-password       = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-repo-uri              = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-aws-access-key-id     = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-aws-secret-access-key = { format = "yaml"; sopsFile = ../secrets.yaml; };
    backrest-gotify-token          = { format = "yaml"; sopsFile = ../secrets.yaml; };
  };

  # Rendered at runtime with real secret values — written to zstorage (LUKS-encrypted).
  sops.templates."backrest-config.json" = {
    content = builtins.toJSON {
      version  = 4;
      modno    = 1;
      instance = "ligma";
      auth.disabled = true;
      repos = [
        {
          id       = "ligma-s3";
          uri            = config.sops.placeholder.backrest-repo-uri;
          autoInitialize = true;
          password = config.sops.placeholder.backrest-restic-password;
          env = [
            "AWS_ACCESS_KEY_ID=${config.sops.placeholder.backrest-aws-access-key-id}"
            "AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backrest-aws-secret-access-key}"
          ];
          prunePolicy.schedule.cron = "0 5 * * *";
        }
      ];
      plans = [
        {
          id   = "ligma-daily";
          repo = "ligma-s3";
          paths = [ "/ligma" ];
          schedule.cron = "0 4 * * *";
          retention.policyTimeBucketed = {
            daily   = 30;
            weekly  = 8;
            monthly = 12;
          };
          hooks = [
            {
              conditions = [ "CONDITION_ANY_ERROR" ];
              actionGotify = {
                baseUrl       = "https://gotify.makifun.se";
                token         = config.sops.placeholder.backrest-gotify-token;
                titleTemplate = "Backrest: {{ .Plan.Id }} failed";
                bodyTemplate  = "{{ .Error }}";
                priority      = 7;
              };
            }
          ];
        }
      ];
    };
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
    after       = [ "local-fs.target" "sops-nix.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      dest="${backrestBase}/config/config.json"
      if [ ! -f "$dest" ]; then
        cp ${config.sops.templates."backrest-config.json".path} "$dest"
        chmod 640 "$dest"
      fi
    '';
  };

  virtualisation.oci-containers.containers.backrest = {
    image   = "ghcr.io/garethgeorge/backrest:${backrestTag}";
    ports   = [ "127.0.0.1:${toString backrestPort}:9898" ];
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
