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
      # 100 G data disk (scsi1, serial=bofa) — all app data + PostgreSQL
      bofa = {
        type = "disk";
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_bofa";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "crypted_bofa";
                settings.allowDiscards = true;
                settings.crypttabExtraOpts = [ "timeout=0" ];
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/bofa";
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
