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
    ./dns-records.nix
    #./apps/autobrr.nix
    ./apps/backrest-extra.nix
    ./apps/beszel-extra.nix
    ./apps/cloud-mount.nix
    #./apps/gluetun.nix
    ./apps/nfs.nix
    #./apps/nzbget.nix
    #./apps/prowlarr.nix
    #./apps/qbittorrent.nix
    #./apps/qui.nix
    ./apps/traefik.nix
    #./apps/trawl.nix
    #./apps/unpackerr.nix
  ];
  networking = {
    hostName = "arrma";
    useDHCP = true;
    hostId = "d0fa50f0";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "26.11";
}
