{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Realtek RTL8111/8168 NIC — must be in initrd for LUKS unlock SSH on :2222.
  boot.initrd.kernelModules = [ "r8169" ];
  imports = [
    ./disko-config.nix
    ../../common
    ../../modules/rclone.nix
    ../../modules/samba.nix
    ./apps/beszel-extra.nix
    ./apps/rclone-extra.nix
    ./apps/samba-extra.nix
  ];
  networking = {
    hostName = "storma";
    useDHCP = true;
    hostId = "c01d5701";
  };
  systemd.services.console-blanking = {
    description = "Blank console after 5 minutes";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/setterm --blank 5";
      StandardOutput = "tty";
      TTYPath = "/dev/tty1";
    };
  };

  # rclone FUSE drop during upgrade causes sonarr/radarr to mark media as missing
  system.autoUpgrade.enable = lib.mkForce false;
  system.stateVersion = "26.11";
}
