{ hosts, ... }:
{
  services.samba-cloud.extraHosts = [
    hosts.playma
    hosts.arrma
  ];
}
