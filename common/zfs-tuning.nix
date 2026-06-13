{ lib, ... }:
{
  boot.zfs.forceImportRoot = false;

  # Cap ARC to 512MB. 1GB caused constant arc_prune thrash (40% CPU).
  # Raise this if the VM gets more RAM assigned and arc_prune stays idle.
  boot.kernelParams = [ "zfs.zfs_arc_max=536870912" ];

  boot.extraModprobeConfig = ''
    # Disable prefetcher in VM - prefetching into ARC is less effective
    # when the underlying storage is already virtualised.
    options zfs zfs_prefetch_disable=1
  '';
}
