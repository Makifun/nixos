{ lib, ... }:
{
  # Cap ARC to 1GB so the VM doesn't pressure the Proxmox host.
  # Raise this if the VM gets more RAM assigned.
  boot.kernelParams = [ "zfs.zfs_arc_max=1073741824" ];

  boot.extraModprobeConfig = ''
    # Disable prefetcher in VM - prefetching into ARC is less effective
    # when the underlying storage is already virtualised.
    options zfs zfs_prefetch_disable=1
  '';
}
