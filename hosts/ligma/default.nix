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
    ./sops.nix
    ../../common
    ../../modules/podman.nix
  ];
  networking = {
    hostName = "ligma";
    useDHCP = true;
    hostId = "324bbd6b";
    firewall.allowedTCPPorts = [
      80
      443
      2049
    ];
  };
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/podman"
    ];
    files = [
      "/etc/machine-id"
    ];
  };
  environment.systemPackages = with pkgs; [
    lynis
  ];
  services = {
    qemuGuest.enable = true;
    nfs.server = {
      enable = true;
      exports = ''
        /ligma 10.10.10.0/24(rw,sync,no_subtree_check,no_root_squash)
      '';
    };
  };
  system = {
    stateVersion = "25.11";
    autoUpgrade = {
      flake = "github:makifun/nixos";
      enable = true;
    };
  };
}
