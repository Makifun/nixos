{ config, ... }:
{
  services.traefik.enable = true;

  # Cloudflare DNS API token for wildcard cert challenge.
  # Secret file must contain: CF_DNS_API_TOKEN=<token>
  # Token needs Zone:DNS:Edit permission for makifun.se.
  services.traefik.environmentFiles = [ config.sops.secrets.traefik_env.path ];

  networking.firewall = {
    allowedTCPPorts = [ 80 443 ];
    allowedUDPPorts = [ 443 ]; # HTTP/3 QUIC
  };

  services.traefik.staticConfigOptions = {
    global.sendAnonymousUsage = false;
    log.level = "INFO";

    # Dashboard accessible on port 8080 (firewalled, internal only)
    api = {
      dashboard = true;
      insecure = true;
    };

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

  # htpasswd-format credentials for the dashboard (user:bcrypt_hash per line)
  # Generate with: htpasswd -nbB <user> <password>
  sops.secrets.traefik_dashboard_users = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "traefik";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.traefik-dashboard = {
      rule = "Host(`traefik-ligma.makifun.se`)";
      entryPoints = [ "websecure" ];
      service = "api@internal";
      middlewares = [ "traefik-dashboard-auth" ];
      tls.certResolver = "letsencrypt";
    };
    middlewares.traefik-dashboard-auth.basicAuth = {
      usersFile = config.sops.secrets.traefik_dashboard_users.path;
    };
  };
}
