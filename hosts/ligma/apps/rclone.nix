{ pkgs, ... }:
{
  # Config lives on zstorage (LUKS-encrypted, persists reboots, included in backrest /ligma backup).
  # Writable at runtime so rclone can refresh OAuth tokens without SOPS involvement.
  systemd.tmpfiles.rules = [
    "d /ligma/ligma/rclone 0700 root root - -"
  ];

  systemd.services.rclone-cloud = {
    description = "rclone NFS server for /cloud (port 2050)";
    after = [
      "local-fs.target"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "local-fs.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.rclone}/bin/rclone serve nfs crypt:/"
        + " --config /ligma/ligma/rclone/rclone.conf"
        + " --addr :2050"
        + " --nfs-cache-type disk"
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
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
