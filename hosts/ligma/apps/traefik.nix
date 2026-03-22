{ config, ... }:
{
  services.traefik.enable = true;

  # Cloudflare DNS API token for wildcard cert challenge.
  # Secret file must contain: CF_DNS_API_TOKEN=<token>
  # Token needs Zone:DNS:Edit permission for makifun.se.
  services.traefik.environmentFiles = [ config.sops.secrets.traefik_env.path ];

  services.traefik.staticConfigOptions = {
    global.sendAnonymousUsage = false;
    log.level = "INFO";

    # Dashboard accessible on port 8080 (firewalled, internal only)
    api = {
      dashboard = true;
      insecure = true;
    };

    # Pangolin provides dynamic route config for its tunneled resources
    providers.http = {
      endpoint = "http://127.0.0.1:3000/api/v1/traefik-config";
      pollInterval = "5s";
    };

    # Allow connecting to backends without TLS verification (needed by Pangolin)
    serversTransport.insecureSkipVerify = true;

    entryPoints = {
      web = {
        address = ":80";
        http.redirections.entryPoint = {
          to = "websecure";
          scheme = "https";
          permanent = true;
        };
      };
      websecure = {
        address = ":443";
        http3.advertisedPort = 443;
        # Request wildcard cert proactively (matches Pangolin's prefer_wildcard_cert)
        http.tls = {
          certResolver = "letsencrypt";
          domains = [
            {
              main = "makifun.se";
              sans = [ "*.makifun.se" ];
            }
          ];
        };
      };
    };

    certificatesResolvers.letsencrypt.acme = {
      email = "admin@makifun.se";
      storage = "/var/lib/traefik/acme.json";
      keyType = "EC384";
      dnsChallenge = {
        provider = "cloudflare";
        propagation = {
          delayBeforeChecks = "30s";
          disableChecks = true;
        };
      };
    };

    # Badger plugin — Pangolin's authentication middleware for Traefik
    experimental.plugins.badger = {
      moduleName = "github.com/fosrl/badger";
      version = "v1.2.1";
    };
  };

  # Persist ACME certificates and Traefik state across reboots
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/traefik";
      user = "traefik";
      group = "traefik";
      mode = "0700";
    }
  ];

  # Traefik Cloudflare token (CF_DNS_API_TOKEN=<token>)
  sops.secrets.traefik_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "traefik";
  };
}
