{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    ./dns-records.nix
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
    ./apps/pgadmin.nix
    ./apps/rclone-storma.nix
    ./apps/gotify.nix
    ./apps/homepage.nix
    ./apps/loki.nix
    ./apps/monitoring.nix
    ./apps/opnsense-exporter.nix
    ./apps/pve-exporter.nix
    ./apps/nfs.nix
    ./apps/omni.nix
    #./apps/rclone.nix
    ./apps/renovate.nix
    #./apps/samba.nix
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
  # ARC tuning — ligma now has 16 GB RAM; 6 GB ARC leaves 10 GB for services.
  # Previous 512 MB limit caused constant arc_prune thrash under NFS load.
  boot.kernelParams = [ "zfs.zfs_arc_max=6442450944" ];
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_min=2147483648
    options zfs zfs_prefetch_disable=1
  '';
  boot.initrd.systemd.services."zfs-import-zroot" = {
    after = [ "dev-mapper-crypted_zroot.device" ];
    requires = [ "dev-mapper-crypted_zroot.device" ];
  };
}
