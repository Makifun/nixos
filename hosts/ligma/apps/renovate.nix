{
  baseFacts,
  config,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  # renovate: datasource=docker depName=ghcr.io/renovatebot/renovate
  renovateTag = "44.30.4";
  dataDir = "/${hostname}/${hostname}/renovate";
  tokenFile = "${dataDir}/token";
  githubTokenFile = config.sops.secrets."renovate-github-token".path;
  renovateConfig = pkgs.writeText "renovate-config.yaml" ''
    platform: gitea
    endpoint: https://git.${baseFacts.domainName}/
    gitAuthor: "Renovate Bot <renovate@${baseFacts.domainName}>"
    baseDir: /data
    binarySource: global
    prHourlyLimit: 0
    prConcurrentLimit: 0
    hostRules:
      - matchHost: https://git.${baseFacts.domainName}
        hostType: docker
        username: renovate-bot
        password: "{{ env.RENOVATE_TOKEN }}"
      - matchHost: https://github.com
        token: "{{ env.GITHUB_COM_TOKEN }}"
    repositories:
      - "makifun/authentik"
      - "makifun/makiplex-bot"
      - "makifun/sugma"
    onboarding: true
    requireConfig: optional
  '';
in
{
  sops.secrets."renovate-github-token" = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = config.services.forgejo.user;
  };

  systemd.tmpfiles.rules = [
    "d '${dataDir}' 0750 ${config.services.forgejo.user} ${config.services.forgejo.group} - -"
  ];

  systemd.services.renovate = {
    description = "Renovate dependency updater";
    after = [
      "network-online.target"
      "forgejo-provision.service"
    ];
    wants = [ "network-online.target" ];
    path = [ pkgs.podman ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -s ${tokenFile} ]; then
        echo "renovate: token not yet provisioned, skipping" >&2
        exit 0
      fi
      podman run --rm \
        --user "$(id -u ${config.services.forgejo.user})" \
        -e RENOVATE_TOKEN="$(cat ${tokenFile})" \
        -e GITHUB_COM_TOKEN="$(cat ${githubTokenFile})" \
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
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5min";
    };
  };
}
