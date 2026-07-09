{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disko-config.nix
    ../../common
    ../../modules/podman.nix
    ./apps/backrest-bofa.nix
    ./apps/apprise.nix
    ./apps/authentik.nix
    ./apps/backrest.nix
    ./apps/beszel.nix
    ./apps/distribution.nix
    ./apps/forgejo.nix
    ./apps/gotify.nix
    ./apps/homepage.nix
    ./apps/loki.nix
    ./apps/monitoring.nix
    ./apps/opnsense-exporter.nix
    #./apps/netbird.nix
    ./apps/nfs.nix
    ./apps/omni.nix
    ./apps/rclone.nix
    ./apps/renovate.nix
    ./apps/samba.nix
    ./apps/syncstorage.nix
    ./apps/technitium.nix
    ./apps/traefik.nix
    ./apps/unifi.nix
    ./apps/vaultwarden.nix
    ./apps/watchyourlan.nix
  ];
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
  sops.secrets.initrd_ssh_host_ed25519_key = {
    format = "yaml";
    sopsFile = ./secrets.yaml;
  };
  services.journald.extraConfig = ''
    SystemMaxUse=512M
    MaxRetentionSec=7day
    MaxFileSec=1day
  '';

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma' 0755 root root - -"
  ];
  networking = {
    hostName = "ligma";
    useDHCP = true;
    hostId = "324bbd6b";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "25.11";

  # ZFS — ligma-only (bofa uses XFS).
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/mapper";
  boot.zfs.forceImportRoot = false;
  # Cap ARC to 512 MB. 1 GB caused constant arc_prune thrash (40% CPU).
  boot.kernelParams = [ "zfs.zfs_arc_max=536870912" ];
  boot.extraModprobeConfig = ''
    options zfs zfs_prefetch_disable=1
  '';
  boot.initrd.systemd.services."zfs-import-zroot" = {
    after = [ "dev-mapper-crypted_zroot.device" ];
    requires = [ "dev-mapper-crypted_zroot.device" ];
  };
}
