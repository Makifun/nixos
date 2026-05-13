{ config, pkgs, ... }:
let
  # renovate: datasource=docker depName=ghcr.io/renovatebot/renovate
  renovateTag = "43.176.9";
  dataDir     = "/ligma/ligma/renovate";
  tokenFile   = "${dataDir}/token";
  renovateConfig = pkgs.writeText "renovate-config.yaml" ''
    platform: gitea
    endpoint: https://git.makifun.se/
    gitAuthor: "Renovate Bot <renovate@makifun.se>"
    baseDir: /data
    binarySource: global
    hostRules:
      - matchHost: git.makifun.se
        hostType: docker
        username: renovate-bot
        password: "{{ env.RENOVATE_TOKEN }}"
    repositories:
      - "makifun/authentik"
      - "makifun/graylog"
      - "makifun/makiplex-bot"
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
        -e GOROOT=${pkgs.go}/share/go \
        -v ${renovateConfig}:/config.yaml:ro \
        -v ${dataDir}:/data \
        -v ${pkgs.go}/share/go:${pkgs.go}/share/go:ro \
        -v ${pkgs.go}/share/go/bin/go:/usr/local/bin/go:ro \
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
