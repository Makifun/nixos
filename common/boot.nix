{ config, pkgs, ... }:
{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    supportedFilesystems = [ "zfs" ];
    zfs.devNodes = "/dev/mapper";
    initrd = {
      systemd = {
        enable = true;
        users.root.shell = "/bin/systemd-tty-ask-password-agent";
        # # services."zfs-import-zroot".serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/sleep 10";
        # services."systemd-cryptsetup@crypted_zroot".serviceConfig.TimeoutStartSec = "infinity";
        # services."systemd-cryptsetup@crypted_ligma".serviceConfig.TimeoutStartSec = "infinity";
      };
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          authorizedKeys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA4ulg3WPkj3HMDz3hi1ELphE/BQN5ztOY55JZzNfAih makizen"
          ];
          hostKeys = [ config.sops.secrets."initrd_ssh_host_ed25519_key".path ];
        };
      };
    };
  };
}
