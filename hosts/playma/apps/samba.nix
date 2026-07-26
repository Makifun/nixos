{ ... }:
{
  services.samba = {
    enable = true;
    openFirewall = false;
    nmbd.enable = false;
    settings = {
      global = {
        "server string" = "playma";
        security = "user";
        "map to guest" = "bad user";
        "hosts allow" = "10.10.10.16 10.10.10.26 10.10.10.27 10.10.10.28 127.0.0.1";
        "hosts deny" = "ALL";
      };
      cloud = {
        path = "/cloud";
        browseable = "no";
        "read only" = "no";
        "guest ok" = "yes";
        # Run as root so smbd has full access to the rclone FUSE mount.
        "force user" = "root";
      };
    };
  };

  # SMB over TCP (port 445). No NetBIOS (139) needed for Linux CIFS mounts by IP.
  networking.firewall.allowedTCPPorts = [ 445 ];
}
