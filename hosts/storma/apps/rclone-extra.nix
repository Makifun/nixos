{ ... }:
{
  services.rclone-cloud.vfsCacheMaxSize = "870G";
  services.rclone-cloud.vfsCacheMinFreeSize = "15G";
  services.rclone-cloud.vfsCacheMaxUploadRate = "10M";
  services.rclone-cloud.bwlimit = "20M";
  services.rclone-cloud.transfers = 8;
  services.rclone-cloud.bufferSize = "32M";
}
