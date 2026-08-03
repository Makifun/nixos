{ hosts, ... }:
{
  services.samba-cloud.extraHosts = [
    hosts.playma
    hosts.arrma
  ];

  services.samba.settings = {
    cloud = {
      # Buffer 16 MB of writes in smbd memory before flushing to the rclone
      # FUSE mount. Coalesces many small writes into fewer, larger FUSE calls,
      # reducing the number of dirty-file events rclone has to track.
      "write cache size" = "16777216";
    };
  };
}
