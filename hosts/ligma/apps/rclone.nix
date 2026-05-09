{ pkgs, ... }:
{
  # Allow smbd (and other non-root processes) to access the FUSE mount.
  programs.fuse.userAllowOther = true;

  # Config lives on zstorage (LUKS-encrypted, persists reboots, included in backrest /ligma backup).
  # Writable at runtime so rclone can refresh OAuth tokens without SOPS involvement.
  systemd.tmpfiles.rules = [
    "d /cloud 0755 root root - -"
    "d /ligma/ligma/rclone 0700 root root - -"
  ];

  systemd.services.rclone-cloud = {
    description = "rclone S3 FUSE mount at /cloud";
    after = [
      "local-fs.target"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStartPre = "-${pkgs.fuse3}/bin/fusermount3 -uz /cloud";
      ExecStart = "${pkgs.rclone}/bin/rclone mount crypt:/ /cloud"
        + " --config /ligma/ligma/rclone/rclone.conf"
        + " --allow-non-empty"
        + " --allow-other"
        + " --buffer-size 256M"
        + " --bwlimit 25M"
        + " --cache-dir /rclone-cache/cache-dir"
        + " --dir-cache-time 10000h"
        + " --jottacloud-hard-delete"
        + " --log-level INFO"
        + " --poll-interval 10000h"
        + " --transfers 8"
        + " --umask 0000"
        + " --use-mmap"
        + " --vfs-cache-max-age 438300h"
        + " --vfs-cache-max-size 185G"
        + " --vfs-cache-mode full"
        + " --vfs-read-chunk-size 128M"
        + " --vfs-read-chunk-size-limit 1G";
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -uz /cloud";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
