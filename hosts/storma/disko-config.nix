{
  disko.devices = {
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=2G"
        "mode=755"
      ];
    };
    disk.storma = {
      # 120 G SSD (ata, model=ADATA_SP550_1F3520274890) — OS + Apps + Cache
      type = "disk";
      device = "/dev/disk/by-id/ata-ADATA_SP550_1F3520274890";
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
              name = "crypted_storma";
              settings.allowDiscards = true;
              content = {
                type = "lvm_pv";
                vg = "vg_storma";
              };
            };
          };
        };
      };
    };
    lvm_vg.vg_storma = {
      type = "lvm_vg";
      lvs = {
        nix = {
          size = "15G";
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
          size = "5G";
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
        storma = {
          size = "5G";
          content = {
            type = "filesystem";
            format = "xfs";
            mountpoint = "/storma";
            mountOptions = [
              "noatime"
              "discard"
            ];
          };
        };
        rclone-cache = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "xfs";
            mountpoint = "/rclone-cache";
            mountOptions = [
              "noatime"
              "discard"
              "logbufs=8"
              "logbsize=256k"
              "allocsize=64M"
            ];
          };
        };
      };
    };
  };
  fileSystems."/persist".neededForBoot = true;
}
