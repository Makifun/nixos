{ ... }:
{
  services.rclone-cloud.vfsCacheMaxSize = "870G";
  services.rclone-cloud.vfsCacheMinFreeSize = "30G";
  services.rclone-cloud.bwlimit = "25M";
  services.rclone-cloud.transfers = 20;
  services.rclone-cloud.bufferSize = "32M";
  services.rclone-cloud.vfsCachePollInterval = "30s";
  # Delay upload start so the smbd write phase completes first, avoiding
  # simultaneous disk reads (upload) and disk writes (SMB ingest).
  services.rclone-cloud.vfsWriteBack = "2m";
  # Cap rclone's write rate to the cache LV so concurrent smbd threads don't
  # pile up in D state waiting for disk IO. Creates natural backpressure on
  # the Samba clients (arrma/playma) without requiring tc rules.
  services.rclone-cloud.ioWriteBandwidthMax = [ "/dev/vg_storma/rclone-cache 50M" ];
}
