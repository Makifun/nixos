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
        # sulogin writes "cannot open access to console, the root account is locked"
        # to stderr. Null stderr to suppress it; sulogin still exits immediately so
        # the TTY is released and the LUKS password prompt remains accessible.
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
