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
                settings.crypttabExtraOpts = [ "timeout=0" ];
                content = {
                  type = "lvm_pv";
                  vg = "vg_nixos";
                };
              };
            };
          };
        };
      };
      # 50 G SSD (scsi1, serial=arrma) — app data
      arrma = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_arrma";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_arrma";
                settings.allowDiscards = true;
                settings.crypttabExtraOpts = [ "timeout=0" ];
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/arrma";
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
      # 4 T HDD (scsi2, serial=slowmeme) — torrent downloads, LUKS+XFS.
      slowmeme = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_slowmeme";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_slowmeme";
                settings.allowDiscards = true;
                settings.crypttabExtraOpts = [ "timeout=0" ];
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/slowmeme";
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
      # 400 G SSD (scsi3, serial=nicememe) — NZBget downloads, LUKS+XFS.
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
