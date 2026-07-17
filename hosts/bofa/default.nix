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
    ./apps/backrest.nix
    ./apps/beszel.nix
    ./apps/timescaledb.nix
    ./apps/pg-dump.nix
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
    "d '/bofa/bofa' 0755 root root - -"
  ];
  networking = {
    hostName = "bofa";
    useDHCP = true;
    hostId = "b0fab0fa";
  };
  services.qemuGuest.enable = true;
  system.stateVersion = "25.11";

  # Override registry mirrors — on bofa these are remote HTTPS endpoints, not localhost.
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
