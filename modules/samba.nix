{
  config,
  lib,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  cfg = config.services.samba-cloud;
  allowedHosts = [
    hosts.sugma01
    hosts.sugma02
    hosts.sugma03
  ]
  ++ cfg.extraHosts;
in
{
  options.services.samba-cloud = {
    extraHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  config = {
    services.samba = {
      enable = true;
      openFirewall = false;
      nmbd.enable = false;
      settings = {
        global = {
          "server string" = hostname;
          security = "user";
          "map to guest" = "bad user";
          "hosts allow" = lib.concatStringsSep " " (allowedHosts ++ [ "127.0.0.1" ]);
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
    networking.firewall.extraInputRules = ''
      ip saddr { ${lib.concatStringsSep ", " allowedHosts} } tcp dport 445 accept
    '';
  };
}
