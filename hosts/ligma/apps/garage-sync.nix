{
  baseFacts,
  config,
  lib,
  pkgs,
  ...
}:
let
  # Every Garage bucket. Each one needs a rclone-config-offsite-<bucket> secret.
  buckets = [
    "backrest"
    "pgbackweb"
    "pg-general-apps"
  ];
  secret = name: {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  # 67 MB/s; rclone's M suffix is MiB, so give bytes. Buckets sync one at a time.
  bwlimit = "67000000B";
  confPath = bucket: config.sops.templates."rclone-garage-offsite-${bucket}.conf".path;
in
{
  sops.secrets = lib.genAttrs (
    [
      "garage-backrest-access-key"
      "garage-backrest-secret-key"
    ]
    ++ map (bucket: "rclone-config-offsite-${bucket}") buckets
  ) secret;

  # Each rclone config: shared [garage] section + per-destination [offsite]+[chunker] blob.
  sops.templates = lib.listToAttrs (
    map (bucket: {
      name = "rclone-garage-offsite-${bucket}.conf";
      value.content = ''
        [garage]
        type = s3
        provider = Other
        access_key_id = ${config.sops.placeholder.garage-backrest-access-key}
        secret_access_key = ${config.sops.placeholder.garage-backrest-secret-key}
        endpoint = https://s3.${baseFacts.domainName}
        region = garage
        no_check_bucket = true

        ${config.sops.placeholder."rclone-config-offsite-${bucket}"}
      '';
    }) buckets
  );

  systemd.services.garage-offsite-sync = {
    description = "Sync Garage buckets to offsite via chunker";
    after = [
      "network-online.target"
      "sops-nix.service"
    ];
    wants = [ "network-online.target" ];
    unitConfig.OnFailure = "garage-offsite-sync-notify.service";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "garage-offsite-sync" ''
        set -e
        ${lib.concatMapStrings (bucket: ''
          ${pkgs.rclone}/bin/rclone sync garage:${bucket} chunker: \
            --config ${confPath bucket} --transfers 4 --log-level INFO \
            --bwlimit ${bwlimit}
        '') buckets}
      '';
    };
  };

  systemd.services.garage-offsite-sync-notify = {
    description = "Gotify notification for garage-offsite-sync failure";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "garage-offsite-sync-notify" ''
        TOKEN=$(< ${config.sops.secrets.backrest-gotify-token.path})
        ${pkgs.curl}/bin/curl -sf \
          "https://gotify.${baseFacts.domainName}/message?token=$TOKEN" \
          -F "title=Garage offsite sync failed" \
          -F "message=garage-offsite-sync.service failed on $(hostname). Check: journalctl -u garage-offsite-sync" \
          -F "priority=7"
      '';
    };
  };

  systemd.timers.garage-offsite-sync = {
    description = "Nightly Garage → offsite sync";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* *:15:00 UTC";
      Persistent = true;
    };
  };
}
