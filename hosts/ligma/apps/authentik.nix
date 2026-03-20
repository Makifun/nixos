{ config, ... }:
{
  services.authentik = {
    enable = true;
    # Secret file must contain:
    #   AUTHENTIK_SECRET_KEY=<random 50+ char string>
    #   AUTHENTIK_POSTGRESQL__PASSWORD=<random password>
    environmentFile = config.sops.secrets.authentik_env.path;
    settings = {
      disable_startup_analytics = true;
      avatars = "none";
      postgresql = {
        host = "/run/postgresql";
        user = "authentik";
        name = "authentik";
        # password comes from environmentFile
      };
    };
  };

  # PostgreSQL for Authentik — store data on the persistent ZFS pool
  services.postgresql = {
    enable = true;
    dataDir = "/ligma/ligma/authentik/postgresql";
    ensureDatabases = [ "authentik" ];
    ensureUsers = [
      {
        name = "authentik";
        ensureDBOwnership = true;
      }
    ];
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/authentik' 0750 root root - -"
    "d '/ligma/ligma/authentik/postgresql' 0700 postgres postgres - -"
  ];

  # Declare user early so SOPS can assign secret ownership before authentik-nix does
  users.users.authentik = {
    isSystemUser = true;
    group = "authentik";
  };
  users.groups.authentik = { };

  sops.secrets.authentik_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "authentik";
  };
}
