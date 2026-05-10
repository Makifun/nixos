{ config, pkgs, ... }:
let
  # renovate: datasource=docker depName=ghcr.io/renovatebot/renovate
  renovateTag = "43.170.19";
  dataDir     = "/ligma/ligma/renovate";
  renovateConfig = pkgs.writeText "renovate-config.yaml" ''
    platform: gitea
    endpoint: https://git.makifun.se/
    gitAuthor: "Renovate Bot <renovate@makifun.se>"
    baseDir: /data
    autodiscover: true
    autodiscoverFilter:
      - "**"
    onboarding: true
    requireConfig: optional
  '';
in
{
  sops.secrets.renovate-token = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.templates."renovate.env" = {
    mode    = "0600";
    content = ''
      RENOVATE_TOKEN=${config.sops.placeholder.renovate-token}
      RENOVATE_CONFIG_FILE=/config.yaml
    '';
  };

  systemd.tmpfiles.rules = [
    "d '${dataDir}' 0750 root root - -"
  ];

  systemd.services.renovate = {
    description = "Renovate dependency updater";
    after       = [ "network-online.target" "sops-nix.service" ];
    wants       = [ "network-online.target" ];
    path        = [ pkgs.podman ];
    serviceConfig.Type = "oneshot";
    script = ''
      podman run --rm \
        --env-file ${config.sops.templates."renovate.env".path} \
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
