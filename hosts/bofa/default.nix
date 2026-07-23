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
    ./apps/pg-arrs.nix
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

}
