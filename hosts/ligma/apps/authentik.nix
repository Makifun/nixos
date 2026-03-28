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
    "d '/ligma/ligma/authentik' 0755 root root - -"
  ];

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

  services.traefik.dynamicConfigOptions.http = {
    routers.authentik = {
      rule = "Host(`auth2.makifun.se`)";
      entryPoints = [ "websecure" ];
      service = "authentik";
      tls.certResolver = "letsencrypt";
    };
    services.authentik.loadBalancer.servers = [ { url = "http://127.0.0.1:9000"; } ];
  };
}
