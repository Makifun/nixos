{ config, pkgs, ... }:
{
  # Allow non-root users (NFS server) to access the FUSE mount.
  programs.fuse.userAllowOther = true;

  sops.secrets.rclone-config = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    # rclone config is an INI file; store as a YAML literal block in secrets.yaml:
    #   rclone-config: |
    #     [cloud]
    #     type = s3
    #     provider = Other
    #     access_key_id = YOUR_KEY
    #     secret_access_key = YOUR_SECRET
    #     endpoint = YOUR_ENDPOINT
    #     region = auto
  };

  systemd.tmpfiles.rules = [
    "d /cloud 0755 root root - -"
  ];

  systemd.services.rclone-cloud = {
    description = "rclone S3 mount at /cloud";
    after = [
      "local-fs.target"
      "network-online.target"
      "sops-nix.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "sops-nix.service" "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${pkgs.rclone}/bin/rclone mount cloud: /cloud"
        + " --config ${config.sops.secrets.rclone-config.path}"
        + " --allow-other"
        + " --vfs-cache-mode full"
        + " --cache-dir /rclone-cache"
        + " --dir-cache-time 1h"
        + " --poll-interval 15m"
        + " --vfs-read-chunk-size 128M"
        + " --buffer-size 256M"
        + " --transfers 8"
        + " --log-level INFO";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
