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
    ./dns-records.nix
    ../../common
    ./apps/apprise.nix
    ./apps/authentik.nix
    ./apps/backrest-extra.nix
    ./apps/beszel-server.nix
    ./apps/distribution.nix
    ./apps/forgejo.nix
    ./apps/garage.nix
    ./apps/garage-sync.nix
    ./apps/gotify.nix
    ./apps/homepage.nix
    #./apps/infisical.nix
    ./apps/loki.nix
    ./apps/monitoring.nix
    ./apps/omni.nix
    ./apps/opnsense-exporter.nix
    ./apps/pgadmin.nix
    ./apps/pve-exporter.nix
    ./apps/traefik-backrest-bofa.nix
    #./apps/traefik-pgbackweb-bofa.nix
    ./apps/traefik-backrest-ligma.nix
    ./apps/traefik-backrest-playma.nix
    ./apps/traefik-rclone-playma.nix
    ./apps/traefik-technitium.nix
    ./apps/traefik.nix
    ./apps/unifi.nix
    ./apps/vaultwarden.nix
    ./apps/watchyourlan.nix
  ];
  networking = {
    hostName = "ligma";
    useDHCP = true;
    hostId = "324bbd6b";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "25.11";

  # ZFS
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/mapper";
  boot.zfs.forceImportRoot = false;
  # ARC tuning — 4 GB max (balloon floor is 12 GB; 6 GB was sized for 16 GB)
  boot.kernelParams = [ "zfs.zfs_arc_max=4294967296" ];
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_min=2147483648
    options zfs zfs_prefetch_disable=1
  '';
  boot.initrd.systemd.services."zfs-import-zroot" = {
    after = [ "dev-mapper-crypted_zroot.device" ];
    requires = [ "dev-mapper-crypted_zroot.device" ];
  };
}
