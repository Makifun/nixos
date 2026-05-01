{
  disko.devices = {
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=2G"
        "mode=755"
      ];
    };
    disk = {
      main = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_nixos";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_zroot";
                settings.allowDiscards = true;
                content = {
                  type = "zfs";
                  pool = "zroot";
                };
              };
            };
          };
        };
      };
      storage = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_ligma";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_ligma";
                settings.allowDiscards = true;
                content = {
                  type = "zfs";
                  pool = "zstorage";
                };
              };
            };
          };
        };
      };
      # 200G SSD (scsi2, serial=cache) — rclone VFS cache, LUKS-encrypted.
      # New VM: disko formats on install. Existing VM: format manually first:
      #   parted /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache -- mklabel gpt
      #   parted /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache -- mkpart primary 1MiB 100%
      #   cryptsetup luksFormat /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache-part1
      #   cryptsetup open /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache-part1 crypted_cache
      #   mkfs.ext4 /dev/mapper/crypted_cache
      #   cryptsetup close crypted_cache
      cache = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_cache";
                settings.allowDiscards = true;
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/rclone-cache";
                  mountOptions = [ "defaults" "discard" ];
                };
              };
            };
          };
        };
      };
    };
    zpool = {
      zroot = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          xattr = "sa";
        };
        datasets = {
          nix = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.mountpoint = "legacy";
          };
          persist = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options.mountpoint = "legacy";
          };
          reserved = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              refreservation = "10G";
            };
          };
        };
      };
      zstorage = {
        type = "zpool";
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          xattr = "sa";
        };
        datasets = {
          ligma = {
            type = "zfs_fs";
            mountpoint = "/ligma";
            options.mountpoint = "legacy";
          };
          reserved = {
            type = "zfs_fs";
            options = {
              mountpoint = "none";
              refreservation = "5G";
            };
          };
        };
      };
    };
  };
  fileSystems."/persist".neededForBoot = true;
  services = {
    zfs.autoScrub.enable = true;
    zfs.trim.enable = true;
  };
}
