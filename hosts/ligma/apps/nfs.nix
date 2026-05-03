{ ... }:
{
  systemd.tmpfiles.rules = [
    "d '/ligma/sugma' 0755 root root - -"
  ];

  # NFSv3 requires rpcbind (111) in addition to nfsd (2049).
  # NFSv3 is stateless — clients auto-recover stale handles by re-traversing from root.
  # This is important for /cloud which is a rclone FUSE re-export: VFS cache eviction
  # regenerates inodes, causing ESTALE on idle paths. NFSv3 clients recover transparently;
  # NFSv4 clients do not.
  networking.firewall.allowedTCPPorts = [ 111 2049 ];
  networking.firewall.allowedUDPPorts = [ 111 2049 ];

  services.nfs.server = {
    enable = true;
    # fsid=100 kept on /cloud for FUSE export stability (stable filesystem ID).
    exports = ''
      /ligma/sugma 10.10.10.26(rw,sync,no_subtree_check,no_root_squash) 10.10.10.27(rw,sync,no_subtree_check,no_root_squash) 10.10.10.28(rw,sync,no_subtree_check,no_root_squash)
      /cloud 10.10.10.16(rw,sync,no_subtree_check,no_root_squash,fsid=100)
    '';
  };
}
