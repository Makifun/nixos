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

  # NFSv4 only — sugma k8s negotiates v4, jonny uses CIFS (Samba). Port 2049 only.
  networking.firewall.allowedTCPPorts = [ 2049 ];
  networking.firewall.allowedUDPPorts = [ 2049 ];

  services.nfs.server = {
    enable = true;
    exports = ''
      /ligma/sugma 10.10.10.26(rw,sync,no_subtree_check,no_root_squash) 10.10.10.27(rw,sync,no_subtree_check,no_root_squash) 10.10.10.28(rw,sync,no_subtree_check,no_root_squash)
    '';
  };
}
