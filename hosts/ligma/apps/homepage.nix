{ config, ... }:
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
  };

  systemd.services.homepage-dashboard = {
    environment = {
      # Config and data directory — create YAML files here to configure homepage.
      HOMEPAGE_CONFIG_DIR = "/ligma/ligma/homepage";
      HOMEPAGE_ALLOWED_HOSTS = "homepage2.makifun.se";
    };
    serviceConfig.EnvironmentFile = config.sops.secrets.homepage-env.path;
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/homepage' 0755 root root - -"
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
