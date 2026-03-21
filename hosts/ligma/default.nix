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
    ./overlays.nix
    ../../common
    ../../modules/podman.nix
    ./apps/forgejo.nix
    ./apps/pangolin.nix
    ./apps/authentik.nix
    ./apps/vaultwarden.nix
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

  sops.secrets.initrd_ssh_host_ed25519_key = {
    format = "yaml";
    sopsFile = ./secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma' 0755 root root - -"
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
      randomizedDelaySec = "30min";
      allowReboot = false;
      rebootWindow = {
        lower = "03:00";
        upper = "06:00";
      };
    };
  };
}
