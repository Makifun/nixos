{ config, pkgs, ... }:
{
  # Allow non-root users (NFS server) to access the FUSE mount.
  programs.fuse.userAllowOther = true;

  sops.secrets.rclone-config = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d /cloud 0755 root root - -"
  ];

  # NFS must start after rclone so it exports the FUSE mount, not the empty tmpfs.
  systemd.services.nfs-server.after = [ "rclone-cloud.service" ];

  systemd.services.rclone-cloud = {
    description = "rclone S3 mount at /cloud";
    after = [
      "local-fs.target"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = "${pkgs.rclone}/bin/rclone mount crypt:/ /cloud"
        + " --config ${config.sops.secrets.rclone-config.path}"
        + " --allow-non-empty"
        + " --allow-other"
        + " --buffer-size 256M"
        + " --bwlimit 25M"
        + " --cache-dir /rclone-cache"
        + " --dir-cache-time 10000h"
        + " --log-level INFO"
        + " --poll-interval 5m"
        + " --transfers 8"
        + " --umask 0000"
        + " --use-mmap"
        + " --vfs-cache-max-age 438300h"
        + " --vfs-cache-max-size 185G"
        + " --vfs-cache-mode full"
        + " --vfs-read-chunk-size 128M"
        + " --vfs-read-chunk-size-limit 1G";
      ExecStartPost = "${pkgs.nfs-utils}/bin/exportfs -r";
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -u /cloud";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
