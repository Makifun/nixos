{ ... }:
{
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/images' 0755 root root - -"
  ];

  virtualisation = {
    containers = {
      enable = true;
      storage.settings.storage = {
        driver    = "overlay";
        graphRoot = "/ligma/ligma/images";
      };
    };
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };
}
