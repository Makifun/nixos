{ config, lib, ... }:
{
  # Authentik API token for the homepage widget.
  # Retrieve from Terraform: tofu output -raw homepage_token
  # Add to secrets.yaml: homepage-env: "HOMEPAGE_VAR_AUTHENTIK_TOKEN=<token>"
  sops.secrets.homepage-env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "localhost:8082,127.0.0.1:8082,homepage2.makifun.se";
    environmentFiles = [ config.sops.secrets.homepage-env.path ];
  };

  # Disable DynamicUser so we can use a static user with a persistent directory.
  # Same pattern as gitea-runner — DynamicUser can't own pre-created paths on zstorage.
  users.users.homepage-dashboard = {
    isSystemUser = true;
    group = "homepage-dashboard";
  };
  users.groups.homepage-dashboard = { };

  systemd.services.homepage-dashboard = {
    environment.HOMEPAGE_CONFIG_DIR = lib.mkForce "/ligma/ligma/homepage";
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "homepage-dashboard";
      Group = lib.mkForce "homepage-dashboard";
      ReadWritePaths = [ "/ligma/ligma/homepage" ];
    };
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/homepage' 0750 homepage-dashboard homepage-dashboard - -"
  ];

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      homepage = {
        rule = "Host(`homepage2.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "homepage-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      homepage-outpost = {
        rule = "Host(`homepage2.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services.homepage-svc.loadBalancer.servers = [
      { url = "http://localhost:8082"; }
    ];
  };
}
