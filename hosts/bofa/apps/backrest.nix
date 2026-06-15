{ config, lib, ... }:
let
  backrestPort = 9898;
  backrestBase = "/bofa/bofa/backrest";
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.13.0";
in
{
  sops.secrets = {
    backrest-restic-password = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
    backrest-repo-uri = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
    backrest-aws-access-key-id = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
    backrest-aws-secret-access-key = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
    backrest-gotify-token = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
  };

  # Rendered at runtime with real secret values — written to /bofa (LUKS-encrypted XFS).
  sops.templates."backrest-config.json" = {
    content = builtins.toJSON {
      version = 4;
      modno = 1;
      instance = "bofa";
      auth.disabled = true;
      repos = [
        {
          id = "bofa-s3";
          uri = config.sops.placeholder.backrest-repo-uri;
          autoInitialize = true;
          password = config.sops.placeholder.backrest-restic-password;
          env = [
            "AWS_ACCESS_KEY_ID=${config.sops.placeholder.backrest-aws-access-key-id}"
            "AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backrest-aws-secret-access-key}"
          ];
          prunePolicy.schedule.cron = "0 6 * * *";
        }
      ];
      plans = [
        {
          id = "bofa-daily";
          repo = "bofa-s3";
          paths = [
            "/bofa/bofa"
          ];
          schedule.cron = "0 5 * * *";
          retention.policyTimeBucketed = {
            daily = 30;
            weekly = 8;
            monthly = 12;
          };
          hooks = [
            {
              conditions = [ "CONDITION_ANY_ERROR" ];
              actionGotify = {
                baseUrl = "https://gotify.makifun.se";
                token = config.sops.placeholder.backrest-gotify-token;
                titleTemplate = "Backrest: {{ .Plan.Id }} failed";
                bodyTemplate = "{{ .Error }}";
                priority = 7;
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
    "d '/bofa/restore'          0755 root root - -"
  ];

  # Write config.json on first start only — backrest may modify it via the UI thereafter.
  systemd.services.backrest-config-init = {
    description = "Initialize backrest config.json";
    wantedBy = [ "podman-backrest.service" ];
    before = [ "podman-backrest.service" ];
    after = [
      "local-fs.target"
      "sops-nix.service"
    ];
    serviceConfig = {
      Type = "oneshot";
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

  # Bind on all interfaces so ligma's Traefik can proxy backrest-bofa.makifun.se.
  virtualisation.oci-containers.containers.backrest = {
    image = "ghcr.io/garethgeorge/backrest:${backrestTag}";
    ports = [ "${toString backrestPort}:9898" ];
    volumes = [
      "${backrestBase}/data:/data"
      "${backrestBase}/config:/config"
      "${backrestBase}/cache:/cache"
      "/bofa/bofa:/bofa/bofa:ro"
      "/bofa/restore:/bofa/restore"
    ];
  };

  # Only ligma's Traefik + homepage needs to reach backrest.
  networking.firewall.extraInputRules = ''
    tcp dport ${toString backrestPort} ip saddr 10.10.10.13/32 accept comment "Backrest from ligma"
  '';
}
