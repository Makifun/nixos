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
      # 50 G SSD (scsi0, serial=nixos) — OS
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
                settings.crypttabExtraOpts = [ "timeout=0" ];
                content = {
                  type = "zfs";
                  pool = "zroot";
                };
              };
            };
          };
        };
      };
      # 100 G SSD (scsi1, serial=ligma) — ZFS storage
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
                settings.crypttabExtraOpts = [ "timeout=0" ];
                content = {
                  type = "zfs";
                  pool = "zstorage";
                };
              };
            };
          };
        };
      };
      # 200 G SSD (scsi3, serial=nicememe) — NZBget downloads, LUKS+XFS.
      nicememe = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_nicememe";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_nicememe";
                settings.allowDiscards = true;
                settings.crypttabExtraOpts = [ "timeout=0" ];
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/nicememe";
                  mountOptions = [
                    "noatime"
                    "nofail"
                  ];
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
