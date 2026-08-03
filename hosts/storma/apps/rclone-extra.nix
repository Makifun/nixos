{ ... }:
{
  services.rclone-cloud.vfsCacheMaxSize = "870G";
  services.rclone-cloud.vfsCacheMinFreeSize = "15G";
  services.rclone-cloud.bwlimit = "25M";
  services.rclone-cloud.transfers = 20;
  services.rclone-cloud.bufferSize = "32M";
  services.rclone-cloud.vfsCachePollInterval = "30s";
}
