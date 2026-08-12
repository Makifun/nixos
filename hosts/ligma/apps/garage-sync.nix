{ baseFacts, config, pkgs, ... }:
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
    description = "Sync Garage backrest bucket to offsite via chunker";
    after = [
      "network-online.target"
      "sops-nix.service"
    ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${pkgs.rclone}/bin/rclone sync garage:backrest chunker:"
        + " --config ${config.sops.templates."rclone-garage-offsite.conf".path}"
        + " --transfers 4"
        + " --log-level INFO";
    };
  };

  # Runs after the latest Backrest host (storma at 05:00 UTC) finishes.
  systemd.timers.garage-offsite-sync = {
    description = "Nightly Garage → offsite sync";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "07:00 UTC";
      Persistent = true;
      RandomizedDelaySec = "15min";
    };
  };
}
