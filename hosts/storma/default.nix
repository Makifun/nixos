{
  config,
  pkgs,
  lib,
  ...
}:
{
  # ASUS K56CB doesn't register EFI NVRAM entries reliably.
  # bootctl always installs to \EFI\BOOT\BOOTX64.EFI regardless; disabling
  # canTouchEfiVariables just skips the NVRAM write that would fail silently.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # Realtek RTL8111/8168 NIC — must be in initrd for LUKS unlock SSH on :2222.
  boot.initrd.kernelModules = [ "r8169" ];
  imports = [
    ./disko-config.nix
    ../../common
    ../../modules/podman.nix
    ../../modules/rclone.nix
    ../../modules/backrest.nix
    ./apps/backrest-extra.nix
    ./apps/beszel.nix
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
  # rclone FUSE drop during upgrade causes sonarr/radarr to mark media as missing
  system.autoUpgrade.enable = lib.mkForce false;

  system.stateVersion = "25.11";

}
