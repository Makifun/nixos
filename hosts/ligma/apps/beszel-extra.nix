{ ... }:
{
  networking.firewall.extraInputRules = ''
    tcp dport 45876 ip saddr 10.10.10.0/24 accept comment "Beszel agent (hub on ligma reaches LAN agents)"
  '';
}
