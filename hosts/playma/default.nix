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
    ../../modules/rclone.nix
    ../../modules/backrest.nix
    ../../modules/beszel.nix
    ./apps/backrest-extra.nix
    ./apps/beszel-extra.nix
    ./apps/samba.nix
    ./apps/plex.nix
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
  # crypted_cache unlocks automatically in initrd via key file — no passphrase
  # prompt needed. Key lives on /persist (unlocked first via crypted_nixos LVM).
  # One-time setup: dd if=/dev/urandom bs=512 count=1 of=/persist/etc/luks/crypted_cache.key
  #                 cryptsetup luksAddKey /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache-part1 /persist/etc/luks/crypted_cache.key
  boot.initrd.secrets."/etc/luks/crypted_cache.key" = "/persist/etc/luks/crypted_cache.key";
  boot.initrd.luks.devices.crypted_cache.keyFile = "/etc/luks/crypted_cache.key";

  systemd.tmpfiles.rules = [
    "d '/playma/playma' 0755 root root - -"
  ];
  networking = {
    hostName = "playma";
    useDHCP = true;
    hostId = "deadb33f";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "26.11";
}
