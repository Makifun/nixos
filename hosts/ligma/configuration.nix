{
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Proxmox QEMU Guest
  services.qemuGuest.enable = true;

  # Bootloader (UEFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Initrd with Network and SSH for LUKS Unlocking
  boot.initrd = {
    systemd.enable = true; 
    systemd.network = {
      enable = true;
      networks."10-eth0" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "yes";
      };
    };
    network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA4ulg3WPkj3HMDz3hi1ELphE/BQN5ztOY55JZzNfAih makizen" ];
        hostKeys = [ ./initrd_ssh_host_ed25519_key ];
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
  networking.hostId = "324bbd6b"; # Required for ZFS

  # Impermanence Logic
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/log"
      "/var/lib/nixos"
      "/var/lib/systemd/coredump"
      "/var/lib/docker" # Keep docker containers persistent
    ];
    files = [
      "/etc/machine-id"
    ];
  };

  # Docker
  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
    storageDriver = "zfs";
  };
  virtualisation.oci-containers.backend = "docker";

  # Dockhand
  virtualisation.oci-containers.containers."dockhand" = {
    image = "fnsys/dockhand:latest";
    ports = [ "3000:3000" ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
      "dockhand_data:/app/data"
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
    3000
    9120
  ];

  # Sudo nopasswd
  security.sudo.wheelNeedsPassword = false;

  # SSH
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

  system.stateVersion = "25.11";
}
