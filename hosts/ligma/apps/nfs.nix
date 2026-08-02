{ config, hosts, ... }:
let
  hostname = config.networking.hostName;
in
{
  systemd.tmpfiles.rules = [
    "d '/${hostname}/sugma' 0755 root root - -"
  ];

  # NFSv4 only — TCP 2049, sugma nodes only.
  networking.firewall.extraInputRules = ''
    ip saddr { ${hosts.sugma01}, ${hosts.sugma02}, ${hosts.sugma03} } tcp dport 2049 accept
  '';

  services.nfs.server = {
    enable = true;
    exports = ''
      /${hostname}/sugma ${hosts.sugma01}(rw,sync,no_subtree_check,no_root_squash) ${hosts.sugma02}(rw,sync,no_subtree_check,no_root_squash) ${hosts.sugma03}(rw,sync,no_subtree_check,no_root_squash)
    '';
  };
  services.nfs.settings.nfsd.threads = 32;
}
