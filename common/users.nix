{ pkgs, ... }:
{
  users.users.makifun = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh = {
      authorizedKeys = {
        keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA4ulg3WPkj3HMDz3hi1ELphE/BQN5ztOY55JZzNfAih makizen"
        ];
      };
    };
  };
  users.mutableUsers = false;
  security.sudo = {
    wheelNeedsPassword = false;
    execWheelOnly = true;
  };
}
