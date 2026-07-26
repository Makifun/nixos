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
  systemd.tmpfiles.rules = [
    "d '/playma/playma' 0755 root root - -"
  ];
  networking = {
    hostName = "playma";
    useDHCP = true;
    hostId = "deadb33f";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "25.11";
}
