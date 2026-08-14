{ ... }:
{
  services.rclone-cloud.vfsCacheMaxSize = "380G";
  services.rclone-cloud.vfsCacheMinFreeSize = "20G";
  services.rclone-cloud.bwlimit = "80M";
  services.rclone-cloud.transfers = 10;
  services.rclone-cloud.bufferSize = "128M";
  services.rclone-cloud.vfsCachePollInterval = "30s";
  services.rclone-cloud.vfsWriteBack = "30m";
}
