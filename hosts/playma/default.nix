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
    ../../modules/backrest.nix
    ../../modules/beszel.nix
    ../../modules/podman.nix
    ../../modules/rclone.nix
    ../../modules/samba.nix
    ./apps/backrest-extra.nix
    ./apps/beszel-extra.nix
    ./apps/plex.nix
    ./apps/plex-trash.nix
  ];
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
