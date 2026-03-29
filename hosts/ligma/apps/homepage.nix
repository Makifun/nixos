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

    widgets = [
      {
        authentik = {
          url = "https://auth2.makifun.se";
          key = "{{HOMEPAGE_VAR_AUTHENTIK_TOKEN}}";
        };
      }
    ];
  };

  # Inject the Authentik API token via environment variable substitution.
  systemd.services.homepage-dashboard.serviceConfig.EnvironmentFile =
    config.sops.secrets.homepage-env.path;

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      homepage = {
        rule = "Host(`homepage.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "homepage-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      homepage-outpost = {
        rule = "Host(`homepage.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
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
