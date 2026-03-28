{ config, ... }:
{
  services.authentik = {
    enable = true;
    environmentFile = config.sops.secrets.authentik_env.path;
    settings = {
      disable_startup_analytics = true;
      avatars = "none";
      postgresql = {
        host = "/run/postgresql";
        user = "authentik";
        name = "authentik";
        # secrets.yaml
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
    "d '/ligma/ligma/authentik/postgresql' 0700 postgres postgres - -"
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
