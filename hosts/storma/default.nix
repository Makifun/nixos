{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Physical machine — Legacy BIOS only, no UEFI firmware support.
  # Override common/boot.nix which enables systemd-boot (EFI-only).
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = lib.mkForce false;
    grub = {
      enable = true;
      device = "/dev/disk/by-id/ata-ADATA_SP550_1F3520274890";
    };
  };
  imports = [
    ./disko-config.nix
    ../../common
    ../../modules/podman.nix
    ./apps/backrest.nix
    ./apps/beszel.nix
    ./apps/rclone.nix
    ./apps/samba.nix
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
    "d '/storma/storma' 0755 root root - -"
  ];
  networking = {
    hostName = "storma";
    useDHCP = true;
    hostId = "c01d5701";
  };
  system.stateVersion = "25.11";

  environment.etc."containers/registries.conf.d/distribution-mirrors.conf".text = lib.mkForce ''
    [[registry]]
    prefix   = "docker.io"
    location = "docker.io"
    [[registry.mirror]]
    location = "dist-dockerhub.mirror.makifun.se"

    [[registry]]
    prefix   = "ghcr.io"
    location = "ghcr.io"
    [[registry.mirror]]
    location = "dist-ghcr.mirror.makifun.se"

    [[registry]]
    prefix   = "lscr.io"
    location = "lscr.io"
    [[registry.mirror]]
    location = "dist-lscr.mirror.makifun.se"

    [[registry]]
    prefix   = "quay.io"
    location = "quay.io"
    [[registry.mirror]]
    location = "dist-quay.mirror.makifun.se"
  '';
}
