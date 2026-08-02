{
  pkgs,
  hosts,
  ...
}:
{
  environment.systemPackages = [ pkgs.cifs-utils ];

  systemd.tmpfiles.rules = [
    "d /cloud 0755 root root - -"
  ];

  systemd.mounts = [
    {
      what = "//${hosts.storma}/cloud";
      where = "/cloud";
      type = "cifs";
      options = "guest,vers=3.0,uid=0,gid=0,file_mode=0755,dir_mode=0775";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      mountConfig.TimeoutSec = "30";
    }
  ];
}
