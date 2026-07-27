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
      nixos = {
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
                name = "crypted_nixos";
                settings.allowDiscards = true;
                content = {
                  type = "lvm_pv";
                  vg = "vg_nixos";
                };
              };
            };
          };
        };
      };
      # 100G SSD (scsi1, serial=playma) — all app data
      playma = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_playma";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_playma";
                settings.allowDiscards = true;
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/playma";
                  mountOptions = [
                    "noatime"
                    "discard"
                  ];
                };
              };
            };
          };
        };
      };
      # 50G SSD (scsi2, serial=transcode) — Plex transcoder scratch
      transcode = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_transcode";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_transcode";
                settings.allowDiscards = true;
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/transcode";
                  mountOptions = [
                    "noatime"
                    "discard"
                  ];
                };
              };
            };
          };
        };
      };
      # 200G SSD (scsi3, serial=cache) — rclone VFS cache, LUKS-encrypted.
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
                  format = "xfs";
                  mountpoint = "/rclone-cache";
                  mountOptions = [
                    "noatime"
                    "discard"
                    "nofail"
                    "allocsize=64M"
                  ];
                };
              };
            };
          };
        };
      };
    };
    lvm_vg = {
      vg_nixos = {
        type = "lvm_vg";
        lvs = {
          nix = {
            size = "25G";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/nix";
              mountOptions = [
                "noatime"
                "discard"
              ];
            };
          };
          persist = {
            size = "100%FREE";
            content = {
              type = "filesystem";
              format = "xfs";
              mountpoint = "/persist";
              mountOptions = [
                "noatime"
                "discard"
              ];
            };
          };
        };
      };
    };
  };
  fileSystems."/persist".neededForBoot = true;
}
