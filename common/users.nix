{ pkgs, ... }:
{
  users.users.makifun = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh = {
      authorizedKeys = {
        keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA4ulg3WPkj3HMDz3hi1ELphE/BQN5ztOY55JZzNfAih makizen"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJbIV/oiJk8EEa50hhncX3z9S4z8F8yrXv8gEEe/FL4s makicachy"
        ];
      };
    };
  };
  users.users.claude = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh = {
      authorizedKeys = {
        keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ/xfy4TiIu8d9kjwBp4utZ2vRtqAy5dw+EZFCzQzJTN claude"
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
