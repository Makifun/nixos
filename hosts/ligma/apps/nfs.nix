{ ... }:
{
  systemd.tmpfiles.rules = [
    "d '/ligma/sugma' 0755 root root - -"
  ];

  # NFSv3 requires rpcbind (111), mountd (20048), and nfsd (2049).
  # lockd/statd ports are pinned so they can be firewalled (otherwise random on each boot).
  services.nfs.server.lockdPort = 4045;
  services.nfs.server.statdPort = 4046;

  networking.firewall.allowedTCPPorts = [ 111 2049 20048 4045 4046 ];
  networking.firewall.allowedUDPPorts = [ 111 2049 20048 4045 4046 ];

  services.nfs.server = {
    enable = true;
    exports = ''
      /ligma/sugma 10.10.10.26(rw,sync,no_subtree_check,no_root_squash) 10.10.10.27(rw,sync,no_subtree_check,no_root_squash) 10.10.10.28(rw,sync,no_subtree_check,no_root_squash)
      /cloud 10.10.10.16(rw,sync,no_subtree_check,no_root_squash,fsid=1337) 10.10.10.26(rw,sync,no_subtree_check,no_root_squash,fsid=1337) 10.10.10.27(rw,sync,no_subtree_check,no_root_squash,fsid=1337) 10.10.10.28(rw,sync,no_subtree_check,no_root_squash,fsid=1337)
    '';
  };
}
