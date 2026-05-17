{ pkgs, ... }:
let
  rclonePort    = 6969;
  metricsPort   = 6970;
in
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
        + " --metrics-addr 127.0.0.1:${toString metricsPort}"
        + " --poll-interval 10000h"
        + " --rc-addr 127.0.0.1:${toString rclonePort}"
        + " --rc-no-auth"
        + " --rc-web-gui-no-open-browser"
        + " --rc-web-gui"
        + " --rc"
        + " --transfers 8"
        + " --umask 0000"
        + " --use-mmap"
        + " --vfs-cache-max-age 438300h"
        + " --vfs-cache-max-size 185G"
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

  # ---------------------------------------------------------------------------
  # Traefik — Authentik SSO gate
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      rclone-outpost = {
        rule        = "Host(`rclone.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority    = 30;
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      rclone = {
        rule        = "Host(`rclone.makifun.se`)";
        priority    = 1;
        entryPoints = [ "websecure" ];
        service     = "rclone-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."rclone-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString rclonePort}"; }
    ];
  };
}
