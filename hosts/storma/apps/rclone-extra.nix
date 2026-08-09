{ ... }:
{
  services.rclone-cloud.vfsCacheMaxSize = "870G";
  services.rclone-cloud.vfsCacheMinFreeSize = "30G";
  services.rclone-cloud.bwlimit = "25M";
  services.rclone-cloud.transfers = 6;
  services.rclone-cloud.bufferSize = "256M";
  services.rclone-cloud.vfsCachePollInterval = "30s";
  # Delay upload start so the smbd write phase completes first, avoiding
  # simultaneous disk reads (upload) and disk writes (SMB ingest).
  services.rclone-cloud.vfsWriteBack = "2m";
}
