{ pkgs, ... }:
let
  rclonePort = 6969;
  metricsPort = 6970;
in
{
  programs.fuse.userAllowOther = true;

  systemd.tmpfiles.rules = [
    "d /cloud 0755 root root - -"
    "d /storma/storma/rclone 0700 root root - -"
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
      ExecStart =
        "${pkgs.rclone}/bin/rclone mount crypt:/ /cloud"
        + " --config /storma/storma/rclone/rclone.conf"
        + " --allow-non-empty"
        + " --allow-other"
        + " --buffer-size 256M"
        + " --bwlimit 25M"
        + " --cache-dir /rclone-cache/cache-dir"
        + " --dir-cache-time 10000h"
        + " --jottacloud-hard-delete"
        + " --log-level INFO"
        + " --metrics-addr 127.0.0.1:${toString metricsPort}"
        + " --poll-interval 10000h"
        + " --rc-addr 0.0.0.0:${toString rclonePort}"
        + " --rc-no-auth"
        + " --rc-web-gui-no-open-browser"
        + " --rc-web-gui"
        + " --rc"
        + " --transfers 8"
        + " --umask 0000"
        + " --use-mmap"
        + " --vfs-cache-max-age 438300h"
        + " --vfs-cache-max-size 185G"
        + " --vfs-cache-min-free-space 10G"
        + " --vfs-cache-mode full"
        + " --vfs-read-chunk-size 128M"
        + " --vfs-read-chunk-size-limit 1G";
      ExecStartPost = "+${pkgs.systemd}/bin/systemctl restart samba-smbd.service";
      ExecStop = "${pkgs.fuse3}/bin/fusermount3 -uz /cloud";
      KillMode = "process";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  # Only ligma's Traefik proxies the rclone RC web UI.
  networking.firewall.extraInputRules = ''
    tcp dport ${toString rclonePort} ip saddr 10.10.10.13/32 accept comment "rclone RC from ligma"
  '';
}
