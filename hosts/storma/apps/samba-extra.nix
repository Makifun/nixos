{ hosts, ... }:
{
  services.samba-cloud.extraHosts = [ hosts.playma ];
}
