{
  baseFacts,
  config,
  hosts,
  lib,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  backrestPort = 9898;
  backrestBase = "/${hostname}/${hostname}/backrest";
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.14.1";

  # Central backup schedule — each host gets a distinct prune hour (UTC) and
  # a distinct minute for the hourly backup, so the hosts never hit S3 at the
  # same time. Add new hosts here. Minute 10 is taken by the k8s cluster.
  scheduleMap = {
    ligma = {
      hour = 3;
      minute = 40;
    };
    playma = {
      hour = 4;
      minute = 50;
    };
  };
  # Hosts not in the map get a stable minute in 5..54 from their name.
  hashedMinute =
    5 + lib.mod (lib.fromHexString (builtins.substring 0 4 (builtins.hashString "sha256" hostname))) 50;
  planId = "${hostname}-hourly";
  repoId = "${hostname}-s3";
  planCron = "${toString config.backrest.scheduleMinute} * * * *";
  pruneCron = "30 ${toString config.backrest.scheduleHour} * * *";
in
{
  options.backrest = {
    scheduleHour = lib.mkOption {
      type = lib.types.ints.between 0 23;
      default = scheduleMap.${hostname}.hour or 5;
      description = "UTC hour for the daily prune (runs at minute 30). Defaults from the central scheduleMap; override only if needed.";
    };
    scheduleMinute = lib.mkOption {
      type = lib.types.ints.between 0 59;
      default = scheduleMap.${hostname}.minute or hashedMinute;
      description = "Minute of the hour for the hourly backup. Defaults from the central scheduleMap; override only if needed.";
    };
    extraPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional paths to include in the backup plan";
    };
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
            id = repoId;
            uri = "${config.sops.placeholder.backrest-repo-uri}${hostname}";
            autoInitialize = true;
            password = config.sops.placeholder.backrest-restic-password;
            env = [
              "AWS_ACCESS_KEY_ID=${config.sops.placeholder.backrest-aws-access-key-id}"
              "AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.backrest-aws-secret-access-key}"
              "AWS_REGION=garage"
            ];
            prunePolicy.schedule.cron = pruneCron;
          }
        ];
        plans = [
          {
            id = planId;
            repo = repoId;
            paths = [ "/${hostname}/${hostname}" ] ++ config.backrest.extraPaths;
            schedule.cron = planCron;
            retention.policyTimeBucketed = {
              hourly = 24;
              daily = 30;
              weekly = 8;
              monthly = 12;
            };
            hooks = [
              {
                conditions = [ "CONDITION_ANY_ERROR" ];
                actionGotify = {
                  baseUrl = "https://gotify.${baseFacts.domainName}";
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
      "d '${backrestBase}/cache'  0750 root root - -"
      "d '${backrestBase}/config' 0750 root root - -"
      "d '${backrestBase}/data'   0750 root root - -"
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
      path = [ pkgs.jq ];
      # The config is seeded once so UI edits survive. Only the schedules are
      # written on every start, so they always follow this file.
      script = ''
        dest="${backrestBase}/config/config.json"
        if [ ! -f "$dest" ]; then
          cp ${config.sops.templates."backrest-config.json".path} "$dest"
          chmod 640 "$dest"
        else
          tmp=$(mktemp "$dest.XXXXXX")
          jq --arg plan ${lib.escapeShellArg planCron} --arg prune ${lib.escapeShellArg pruneCron} '
            (.plans[] | select(.id == "${planId}") | .schedule.cron) = $plan
            | (.repos[] | select(.id == "${repoId}") | .prunePolicy.schedule.cron) = $prune
          ' "$dest" > "$tmp"
          chmod 640 "$tmp"
          mv "$tmp" "$dest"
        fi
      '';
    };

    # Backrest reads config.json only at start.
    systemd.services.podman-backrest.restartTriggers = [
      planCron
      pruneCron
    ];

    virtualisation.oci-containers.containers.backrest = {
      image = "ghcr.io/garethgeorge/backrest:${backrestTag}";
      ports = [ "${toString backrestPort}:9898" ];
      volumes = [
        "${backrestBase}/data:/data"
        "${backrestBase}/config:/config"
        "${backrestBase}/cache:/cache"
        "/${hostname}/${hostname}:/${hostname}/${hostname}:ro"
        "/${hostname}/restore:/${hostname}/restore"
      ];
    };

    networking.firewall.extraInputRules = ''
      tcp dport ${toString backrestPort} ip saddr ${hosts.ligma}/32 accept comment "Backrest from ligma"
    '';
  };
}
