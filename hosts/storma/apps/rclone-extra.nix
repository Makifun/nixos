{ ... }:
{
  services.rclone-cloud.vfsCacheMaxSize = "870G";
  services.rclone-cloud.vfsCacheMinFreeSize = "30G";
  services.rclone-cloud.bwlimit = "25M";
  # 4 concurrent uploads instead of 20 — storma has a spinner; 20 parallel
  # disk reads during upload caused 68% iowait when arr apps were writing
  # large files at the same time.
  services.rclone-cloud.transfers = 4;
  services.rclone-cloud.bufferSize = "32M";
  services.rclone-cloud.vfsCachePollInterval = "30s";
  # Delay upload start so the smbd write phase completes first, avoiding
  # simultaneous disk reads (upload) and disk writes (SMB ingest).
  services.rclone-cloud.vfsWriteBack = "2m";
}
