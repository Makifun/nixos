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
    ../../modules/beszel-agent.nix
    ../../modules/podman.nix
    ./apps/backrest-extra.nix
    ./apps/beszel-extra.nix
    ./apps/gluetun.nix
    ./apps/qbittorrent.nix
    ./apps/byparr.nix
    ./apps/autobrr.nix
    ./apps/qui.nix
    ./apps/prowlarr.nix
    ./apps/unpackerr.nix
  ];
  networking = {
    hostName = "arrma";
    useDHCP = true;
    hostId = "d0fa50f0";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "26.11";
}
