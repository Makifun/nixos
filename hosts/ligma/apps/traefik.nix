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

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      traefik-dashboard = {
        rule = "Host(`traefik-ligma.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "api@internal";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      # Routes the post-login callback back to the embedded outpost.
      # Authentik redirects here after authentication to set the session cookie.
      traefik-dashboard-outpost = {
        rule = "Host(`traefik-ligma.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    middlewares.authentik.forwardAuth = {
      address = "http://localhost:9000/outpost.goauthentik.io/auth/traefik";
      trustForwardHeader = true;
      authResponseHeaders = [
        "X-authentik-username"
        "X-authentik-groups"
        "X-authentik-email"
        "X-authentik-name"
        "X-authentik-uid"
        "X-authentik-jwt"
        "X-authentik-meta-jwks"
        "X-authentik-meta-outpost"
        "X-authentik-meta-provider"
        "X-authentik-meta-app"
        "X-authentik-meta-version"
      ];
    };
    services.authentik-embedded-outpost.loadBalancer.servers = [
      { url = "http://localhost:9000"; }
    ];
  };
}
