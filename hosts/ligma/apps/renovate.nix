{ config, pkgs, ... }:
let
  # renovate: datasource=docker depName=ghcr.io/renovatebot/renovate
  renovateTag = "43.173.5";
  dataDir     = "/ligma/ligma/renovate";
  tokenFile   = "${dataDir}/token";
  renovateConfig = pkgs.writeText "renovate-config.yaml" ''
    platform: gitea
    endpoint: https://git.makifun.se/
    gitAuthor: "Renovate Bot <renovate@makifun.se>"
    baseDir: /data
    repositories:
      - "makifun/authentik"
      - "makifun/graylog"
      - "makifun/makiplex-bot"
      - "makifun/makizen"
      - "makifun/medializr"
      - "makifun/opnsense-config"
      - "makifun/solN-sddm"
      - "makifun/sugma"
    onboarding: true
    requireConfig: optional
  '';
in
{
  systemd.tmpfiles.rules = [
    "d '${dataDir}' 0750 ${config.services.forgejo.user} ${config.services.forgejo.group} - -"
  ];

  systemd.services.renovate = {
    description = "Renovate dependency updater";
    after       = [ "network-online.target" "forgejo-provision.service" ];
    wants       = [ "network-online.target" ];
    path        = [ pkgs.podman ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -s ${tokenFile} ]; then
        echo "renovate: token not yet provisioned, skipping" >&2
        exit 0
      fi
      podman run --rm \
        --user "$(id -u ${config.services.forgejo.user})" \
        -e RENOVATE_TOKEN="$(cat ${tokenFile})" \
        -e RENOVATE_CONFIG_FILE=/config.yaml \
        -v ${renovateConfig}:/config.yaml:ro \
        -v ${dataDir}:/data \
        ghcr.io/renovatebot/renovate:${renovateTag}
    '';
  };

  systemd.timers.renovate = {
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar         = "hourly";
      Persistent         = true;
      RandomizedDelaySec = "5min";
    };
  };
}
