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
        # sulogin outputs "cannot open access to console" when root is locked.
        # sleep infinity alone holds /dev/console (StandardInput=tty is inherited)
        # and blocks the password prompt. Redirect to null to release the TTY.
        services.emergency.serviceConfig = {
          ExecStart = lib.mkForce "-/bin/sleep infinity";
          StandardInput = "null";
          StandardOutput = "null";
          StandardError = "null";
        };
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
