{
  baseFacts,
  config,
  pkgs,
  ...
}:
{
  sops.secrets.garage-backrest-access-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.garage-backrest-secret-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.rclone-config-offsite = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Assembles a complete rclone.conf: [garage] section built from individual
  # key secrets, followed by the offsite blob (must contain [offsite] + [chunker]).
  sops.templates."rclone-garage-offsite.conf" = {
    content = ''
      [garage]
      type = s3
      provider = Other
      access_key_id = ${config.sops.placeholder.garage-backrest-access-key}
      secret_access_key = ${config.sops.placeholder.garage-backrest-secret-key}
      endpoint = https://s3.${baseFacts.domainName}
      region = garage
      no_check_bucket = true

      ${config.sops.placeholder.rclone-config-offsite}
    '';
  };

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
      # The backrest key must have read access to both buckets:
      #   podman exec garage /garage bucket allow pgbackweb --read --key <backrest-key-id>
      # backrest syncs to chunker root; pgbackweb to chunker:pgbackweb/ to keep them separate.
      ExecStart = pkgs.writeShellScript "garage-offsite-sync" ''
        set -e
        CONF=${config.sops.templates."rclone-garage-offsite.conf".path}
        ${pkgs.rclone}/bin/rclone sync garage:backrest chunker: \
          --config "$CONF" --transfers 4 --log-level INFO
        ${pkgs.rclone}/bin/rclone sync garage:pgbackweb chunker:pgbackweb \
          --config "$CONF" --transfers 4 --log-level INFO
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
      OnCalendar = "02:00 UTC";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };
}
