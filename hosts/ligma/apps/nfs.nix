{ ... }:
{
  systemd.tmpfiles.rules = [
    "d '/ligma/sugma' 0755 root root - -"
    # Mount point for bind — actual data lives in old PVC dir (f72d460c)
    "d '/ligma/sugma/miniflux-minifluxdb-data-pvc-c555d26d-c845-4972-b4ca-317a40e0a8e9' 0755 root root - -"
  ];

  # PVC UUID changed after restore; bind old data dir at new path so NFS serves it correctly.
  fileSystems."/ligma/sugma/miniflux-minifluxdb-data-pvc-c555d26d-c845-4972-b4ca-317a40e0a8e9" = {
    device  = "/ligma/sugma/miniflux-minifluxdb-data-pvc-f72d460c-88a7-4acc-8104-853c66caf7f1";
    fsType  = "none";
    options = [ "bind" ];
  };

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
