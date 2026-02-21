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
      "/var/run/docker.sock:/var/run/docker.sock"
      "dockhand_data:/app/data"
    ];
  };

  # Create the network before containers start
  systemd.services.docker-network-komodo = {
    description = "Create the internal docker network for Komodo";
    after = [ "network.target" "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      check=$(${pkgs.docker}/bin/docker network ls -qf name=komodo)
      if [ -z "$check" ]; then
        ${pkgs.docker}/bin/docker network create komodo
      fi
    '';
  };

  # KomodoMongo
  virtualisation.oci-containers.containers."komodomongo" = {
    image = "mongo:latest";
    extraOptions = [ "--network=komodo" ];
    volumes = [
      "komodomongo-data:/data/db"
      "komodomongo-config:/data/configdb"
    ];
    environment = {
      MONGO_INITDB_ROOT_USERNAME = "admin";
      MONGO_INITDB_ROOT_PASSWORD = "password";
    };
  };

  # KomodoCore
  virtualisation.oci-containers.containers."komodocore" = {
    image = "ghcr.io/moghtech/komodo-core:latest";
    ports = [ "9120:9120" ];
    extraOptions = [ "--network=komodo" ];
    dependsOn = [ "komodomongo" ];
    volumes = [
      "komodocore-backups:/backups"
    ];
    environment = {
      KOMODO_DATABASE_ADDRESS = "komodomongo:27017";
      KOMODO_DATABASE_USERNAME = "admin";
      KOMODO_DATABASE_PASSWORD = "password";
    };
  };

  # KomodoPeriphery
  virtualisation.oci-containers.containers."komodoperiphery" = {
    image = "ghcr.io/moghtech/komodo-periphery:latest";
    extraOptions = [ "--network=komodo" ];
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock:ro"
      "komodoperiphery-data:/etc/komodo"
    ];
  };

  systemd.services."docker-komodomongo".after = [ "docker-network-komodo.service" ];
  systemd.services."docker-komodomongo".requires = [ "docker-network-komodo.service" ];

  systemd.services."docker-komodocore".after = [ "docker-network-komodo.service" ];
  systemd.services."docker-komodocore".requires = [ "docker-network-komodo.service" ];

  systemd.services."docker-komodoperiphery".after = [ "docker-network-komodo.service" ];
  systemd.services."docker-komodoperiphery".requires = [ "docker-network-komodo.service" ];

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
