{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    ./disko-config.nix
    ./sops.nix
    ../../common
    ../../modules/podman.nix
  ];

  # Proxmox QEMU Guest
  services.qemuGuest.enable = true;

  # Bootloader (UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Initrd with Network and SSH for LUKS Unlocking
  boot.initrd = {
    systemd = {
      enable = true;
      users.root.shell = "/bin/systemd-tty-ask-password-agent";
      network = {
        enable = true;
        networks."10-dhcp" = {
          networkConfig.DHCP = "yes";
        };
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

  # ZFS
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.devNodes = "/dev/disk/by-id";
  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;

  # Networking
  networking.hostName = "ligma";
  networking.useDHCP = true;
  networking.hostId = "324bbd6b";

  # Impermanence
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

  # NFS
  services.nfs.server = {
    enable = true;
    exports = ''
      /ligma 10.10.10.0/24(rw,sync,no_subtree_check,no_root_squash)
    '';
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [
    80
    443
    2049
  ];

  # Sudo nopasswd
  security.sudo.wheelNeedsPassword = false;

  # SSH Persistence
  systemd.tmpfiles.rules = [
    "d /persist/etc/ssh 0755 root root -"
  ];
  services.openssh = {
    enable = true;
    openFirewall = true;
    hostKeys = [
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
      {
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
        bits = 4096;
      }
    ];
  };

  # Auto upgrade
  system = {
    stateVersion = "25.11";
    autoUpgrade = {
      flake = "github:makifun/nixos";
      enable = true;
    };
  };
}
