{
  config,
  hosts,
  lib,
  ...
}:
let
  hostname = config.networking.hostName;
  backrestPort = 9898;
  backrestBase = "/${hostname}/${hostname}/backrest";
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.14.1";
  scheduleHour = config.backrest.scheduleHour;
in
{
  options.backrest.scheduleHour = lib.mkOption {
    type = lib.types.int;
    default = 5;
    description = "UTC hour for daily backup (prune runs one hour later)";
  };

  config = {
    sops.secrets = {
      backrest-restic-password = {
        format = "yaml";
        sopsFile = ../common/secrets.yaml;
      };
      backrest-repo-uri = {
        format = "yaml";
        sopsFile = ../common/secrets.yaml;
      };
      backrest-aws-access-key-id = {
        format = "yaml";
        sopsFile = ../common/secrets.yaml;
      };
      backrest-aws-secret-access-key = {
        format = "yaml";
        sopsFile = ../common/secrets.yaml;
      };
      backrest-gotify-token = {
        format = "yaml";
        sopsFile = ../common/secrets.yaml;
      };
    };

    sops.templates."backrest-config.json" = {
      content = builtins.toJSON {
        version = 4;
        modno = 1;
        instance = hostname;
        auth.disabled = true;
        repos = [
          {
            id = "${hostname}-s3";
            uri = config.sops.placeholder.backrest-repo-uri;
            autoInitialize = true;
            password = config.sops.placeholder.backrest-restic-password;
            env = [
              "AWS_ACCESS_KEY_ID=${config.sops.placeholder.backrest-aws-access-key-id}"
              "AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backrest-aws-secret-access-key}"
            ];
            prunePolicy.schedule.cron = "30 ${toString scheduleHour} * * *";
          }
        ];
        plans = [
          {
            id = "${hostname}-daily";
            repo = "${hostname}-s3";
            paths = [ "/${hostname}/${hostname}" ];
            schedule.cron = "0 ${toString scheduleHour} * * *";
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
      "d '/${hostname}/restore'   0755 root root - -"
    ];

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

    virtualisation.oci-containers.containers.backrest = {
      image = "ghcr.io/garethgeorge/backrest:${backrestTag}";
      ports = [ "${toString backrestPort}:9898" ];
      volumes = [
        "${backrestBase}/data:/data"
        "${backrestBase}/config:/config"
        "${backrestBase}/cache:/cache"
      ];
    };

    networking.firewall.extraInputRules = ''
      tcp dport ${toString backrestPort} ip saddr ${hosts.ligma}/32 accept comment "Backrest from ligma"
    '';
  };
}
