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
    ./apps/traefik.nix
    ./apps/forgejo.nix
    ./apps/authentik.nix
    ./apps/vaultwarden.nix
    ./apps/homepage.nix
    ./apps/graylog.nix
    ./apps/unifi.nix
    ./apps/beszel.nix
    ./apps/gotify.nix
    ./apps/apprise.nix
    ./apps/backrest.nix
    ./apps/distribution.nix
    ./apps/nfs.nix
    ./apps/vector.nix
    ./apps/autoupgrade-notify.nix
    ./apps/omni.nix
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
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma' 0755 root root - -"
  ];
  networking = {
    hostName = "ligma";
    useDHCP = true;
    hostId = "324bbd6b";
  };
  services.qemuGuest.enable = true;
  system = {
    stateVersion = "25.11";
    autoUpgrade = {
      flake = "github:makifun/nixos";
      enable = true;
      randomizedDelaySec = "30min";
      allowReboot = false;
      rebootWindow = {
        lower = "03:00";
        upper = "06:00";
      };
    };
  };
}
