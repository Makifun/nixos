{ ... }:
{
  services.rclone-cloud.vfsCacheMaxSize = "870G";
  services.rclone-cloud.vfsCacheMinFreeSize = "15G";
  services.rclone-cloud.vfsCacheMaxUploadRate = "8M";
  services.rclone-cloud.bwlimit = "10M";
  services.rclone-cloud.transfers = 2;
  services.rclone-cloud.bufferSize = "32M";
}
