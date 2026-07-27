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
      nixos = {
        type = "disk";
        # 50 G OS disk (scsi0, serial=nixos)
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
                # Single LUKS → LVM so both /nix and /persist share one passphrase.
                content = {
                  type = "lvm_pv";
                  vg = "vg_nixos";
                };
              };
            };
          };
        };
      };
      playma = {
        type = "disk";
        # 100 G data disk (scsi1, serial=playma) — all app data
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
      transcode = {
        type = "disk";
        # 50 G transcode disk (scsi2, serial=transcode) — Plex transcoder scratch
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
      # New VM: disko formats on install. Existing VM: format manually first:
      #   parted /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache -- mklabel gpt
      #   parted /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache -- mkpart primary 1MiB 100%
      #   cryptsetup luksFormat /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache-part1
      #   cryptsetup open /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_cache-part1 crypted_cache
      #   mkfs.ext4 -m 1 /dev/mapper/crypted_cache
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
                  mountOptions = [
                    "defaults"
                    "discard"
                    "nofail"
                  ];
                  extraArgs = [
                    "-m"
                    "1"
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
