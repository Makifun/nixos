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
    ./dns-records.nix
    ./apps/autobrr.nix
    ./apps/backrest-extra.nix
    ./apps/beszel-extra.nix
    ./apps/byparr.nix
    ./apps/cloud-mount.nix
    ./apps/gluetun.nix
    ./apps/nfs.nix
    ./apps/nzbget.nix
    ./apps/prowlarr.nix
    ./apps/qbittorrent.nix
    ./apps/qui.nix
    ./apps/traefik.nix
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
