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
  # One-time setup: mkdir -p /persist/etc/luks
  #                 dd if=/dev/urandom bs=512 count=1 of=/persist/etc/luks/crypted_cache.key
  #                 chmod 400 /persist/etc/luks/crypted_cache.key
  #                 cryptsetup luksAddKey /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache-part1 /persist/etc/luks/crypted_cache.key
  #                 nh os switch --refresh   (embeds key into initrd; run on playma)
  # Guard with pathExists so nixos-anywhere (builds initrd on local machine where
  # the key doesn't exist) doesn't fail on a fresh install.
  boot.initrd.secrets = lib.mkIf (builtins.pathExists "/persist/etc/luks/crypted_cache.key") {
    "/etc/luks/crypted_cache.key" = "/persist/etc/luks/crypted_cache.key";
  };
  boot.initrd.luks.devices.crypted_cache.keyFile =
    lib.mkIf (builtins.pathExists "/persist/etc/luks/crypted_cache.key") "/etc/luks/crypted_cache.key";

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
