{
  config,
  pkgs,
  lib,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  rcloneBase = "/${hostname}/${hostname}/rclone";
  rclonePort = 6969;
  metricsPort = 6970;
  cfg = config.services.rclone-cloud;
in
{
  options.services.rclone-cloud = {
    vfsCacheMaxSize = lib.mkOption {
      type = lib.types.str;
      default = "185G";
    };
    vfsCacheMinFreeSize = lib.mkOption {
      type = lib.types.str;
      default = "10G";
    };
    bwlimit = lib.mkOption {
      type = lib.types.str;
      default = "25M";
    };
    transfers = lib.mkOption {
      type = lib.types.int;
      default = 8;
    };
    bufferSize = lib.mkOption {
      type = lib.types.str;
      default = "256M";
    };
    vfsCachePollInterval = lib.mkOption {
      type = lib.types.str;
      default = "1m";
    };
    vfsWriteBack = lib.mkOption {
      type = lib.types.str;
      default = "5s";
    };
  };

  config = {
    programs.fuse.userAllowOther = true;

    systemd.tmpfiles.rules = [
      "d ${rcloneBase}         0700 root root - -"
      "d /cloud                0755 root root - -"
      "d /rclone-cache         0700 root root - -"
      "d /rclone-cache/tmp     0700 root root - -"
    ];

    sops.secrets.rclone-config-stage = {
      format = "yaml";
      sopsFile = ../common/secrets.yaml;
    };

    sops.secrets.rclone-config-prod = {
      format = "yaml";
      sopsFile = ../common/secrets.yaml;
    };

    systemd.services.rclone-config-init = {
      description = "Bootstrap rclone.conf from sops secret (stage) if missing";
      before = [ "rclone-cloud.service" ];
      requiredBy = [ "rclone-cloud.service" ];
      after = [ "sops-nix.service" ];
      serviceConfig.Type = "oneshot";
      script = ''
        dest=${rcloneBase}/rclone.conf
        if [ ! -f "$dest" ]; then
          install -m 0600 ${config.sops.secrets.rclone-config-stage.path} "$dest"
        fi
      '';
    };

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
          "${pkgs.rclone}/bin/rclone mount chunker:/ /cloud"
          + " --config ${rcloneBase}/rclone.conf"
          + " --allow-non-empty"
          + " --allow-other"
          + " --buffer-size ${cfg.bufferSize}"
          + " --bwlimit ${cfg.bwlimit}"
          + " --cache-dir /rclone-cache/cache-dir"
          + " --dir-cache-time 10000h"
          + " --jottacloud-hard-delete"
          + " --log-level INFO"
          + " --metrics-addr 0.0.0.0:${toString metricsPort}"
          + " --poll-interval 10000h"
          + " --rc-addr 0.0.0.0:${toString rclonePort}"
          + " --rc-web-gui"
          + " --rc-web-gui-no-open-browser"
          + " --rc-no-auth"
          + " --rc-serve"
          + " --rc"
          + " --transfers ${toString cfg.transfers}"
          + " --umask 0000"
          + " --use-mmap"
          + " --vfs-cache-max-age 438300h"
          + " --vfs-cache-max-size ${cfg.vfsCacheMaxSize}"
          + " --vfs-cache-min-free-space ${cfg.vfsCacheMinFreeSize}"
          + " --vfs-cache-mode full"
          + " --vfs-cache-poll-interval ${cfg.vfsCachePollInterval}"
          + " --vfs-read-chunk-size 128M"
          + " --vfs-read-chunk-size-limit 1G"
          + " --vfs-write-back ${cfg.vfsWriteBack}";
        Environment = [
          "HOME=/rclone-cache"
          "TMPDIR=/rclone-cache/tmp"
        ];
        ExecStartPost = lib.mkIf config.services.samba.enable "+${pkgs.systemd}/bin/systemctl restart samba-smbd.service";
        ExecStop = "${pkgs.fuse3}/bin/fusermount3 -uz /cloud";
        KillMode = "process";
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };

    # Only ligma's Traefik proxies the rclone RC web UI.
    networking.firewall.extraInputRules = ''
      tcp dport ${toString rclonePort} ip saddr ${hosts.ligma}/32 accept comment "rclone RC from ligma"
      tcp dport ${toString metricsPort} ip saddr ${hosts.ligma}/32 accept comment "rclone metrics from ligma"
    '';
  };
}
