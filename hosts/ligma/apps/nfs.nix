{ ... }:
{
  systemd.tmpfiles.rules = [
    "d '/ligma/sugma' 0755 root root - -"
  ];

  networking.firewall.allowedTCPPorts = [ 2049 ];

  services.nfs.server = {
    enable = true;
    exports = ''
      /ligma/sugma 10.10.10.26(rw,sync,no_subtree_check,no_root_squash) 10.10.10.27(rw,sync,no_subtree_check,no_root_squash) 10.10.10.28(rw,sync,no_subtree_check,no_root_squash)
      /cloud 10.10.10.16(rw,sync,no_subtree_check,no_root_squash,fsid=100)
    '';
  };
}
