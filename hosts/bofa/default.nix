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
    ../../modules/backrest.nix
    ./apps/backrest-extra.nix
    ./apps/beszel.nix
    ./apps/pg-arrs.nix
    ./apps/pg-dump.nix
    ./apps/timescaledb.nix
  ];
  systemd.tmpfiles.rules = [
    "d '/bofa/bofa' 0755 root root - -"
  ];
  networking = {
    hostName = "bofa";
    useDHCP = true;
    hostId = "b0fab0fa";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "25.11";
}
