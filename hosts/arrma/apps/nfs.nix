{ hosts, ... }:
{
  systemd.tmpfiles.rules = [
    "z '/slowmeme' 0775 1000 1000 - -"
    "z '/nicememe' 0775 1000 1000 - -"
  ];

  networking.firewall.extraInputRules = ''
    ip saddr { ${hosts.sugma01}, ${hosts.sugma02}, ${hosts.sugma03} } tcp dport 2049 accept
  '';

  services.nfs.server = {
    enable = true;
    exports = ''
      /slowmeme ${hosts.sugma01}(rw,async,no_subtree_check,no_root_squash) ${hosts.sugma02}(rw,async,no_subtree_check,no_root_squash) ${hosts.sugma03}(rw,async,no_subtree_check,no_root_squash)
      /nicememe ${hosts.sugma01}(rw,async,no_subtree_check,no_root_squash) ${hosts.sugma02}(rw,async,no_subtree_check,no_root_squash) ${hosts.sugma03}(rw,async,no_subtree_check,no_root_squash)
    '';
  };
  services.nfs.settings.nfsd.threads = 8;
}
