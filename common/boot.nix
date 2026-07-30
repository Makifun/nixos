{ config, lib, ... }:
{
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      systemd = {
        enable = true;
        users.root.shell = "/bin/systemd-tty-ask-password-agent";
        # Device units (dev-mapper-crypted_*.device) have a default timeout (~90s).
        # When they expire, ZFS import fails → /persist mount fails → emergency mode.
        # Setting infinity prevents that cascade; cryptsetup waits for the password
        # however long it takes and the device unit follows without timing out first.
        settings.Manager.DefaultDeviceTimeoutSec = "infinity";
        # Keep stderr suppressed as defence-in-depth in case emergency mode is ever
        # triggered by something else.
        services.emergency.serviceConfig.StandardError = lib.mkForce "null";
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
