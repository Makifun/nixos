{ ... }:
{
  systemd.tmpfiles.rules = [
    "d '/ligma/sugma' 0755 root root - -"
    "z '/slowmeme' 0775 1000 1000 - -"
    "z '/nicememe' 0775 1000 1000 - -"
  ];

  # NFSv4 only — sugma k8s negotiates v4, jonny uses CIFS (Samba). Port 2049 only.
  networking.firewall.allowedTCPPorts = [ 2049 ];
  networking.firewall.allowedUDPPorts = [ 2049 ];

  services.nfs.server = {
    enable = true;
    # async on slowmeme/nicememe: torrent/usenet data tolerates server-crash loss.
    # sync on /ligma/sugma: k8s PVC data (app databases, configs).
    exports = ''
      /ligma/sugma 10.10.10.26(rw,sync,no_subtree_check,no_root_squash) 10.10.10.27(rw,sync,no_subtree_check,no_root_squash) 10.10.10.28(rw,sync,no_subtree_check,no_root_squash)
      /slowmeme 10.10.10.26(rw,async,no_subtree_check,no_root_squash) 10.10.10.27(rw,async,no_subtree_check,no_root_squash) 10.10.10.28(rw,async,no_subtree_check,no_root_squash)
      /nicememe 10.10.10.26(rw,async,no_subtree_check,no_root_squash) 10.10.10.27(rw,async,no_subtree_check,no_root_squash) 10.10.10.28(rw,async,no_subtree_check,no_root_squash)
    '';
    extraNfsdConfig = ''
      threads=32
    '';
  };
}
