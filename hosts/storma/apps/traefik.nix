{ config, ... }:
{
  services.traefik.enable = true;

  services.traefik.environmentFiles = [ config.sops.secrets.traefik_env.path ];

  networking.firewall.extraInputRules = ''
    ip saddr 10.10.10.0/24 tcp dport 80 accept
    ip saddr 10.10.10.0/24 tcp dport 443 accept
    ip saddr 10.10.10.0/24 udp dport 443 accept
    ip saddr 10.10.11.0/24 tcp dport 80 accept
    ip saddr 10.10.11.0/24 tcp dport 443 accept
    ip saddr 10.10.11.0/24 udp dport 443 accept
  '';

  services.traefik.staticConfigOptions = {
    global.sendAnonymousUsage = false;
    log.level = "INFO";

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
        forwardedHeaders.trustedIPs = [ "10.10.10.1/32" ];
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
        propagation.delayBeforeChecks = "30s";
      };
    };
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/traefik";
      user = "traefik";
      group = "traefik";
      mode = "0700";
    }
  ];

  sops.secrets.traefik_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "traefik";
  };

  services.traefik.dynamicConfigOptions.http = {
    middlewares.authentik.forwardAuth = {
      # Authentik runs on ligma — forward auth there.
      address = "http://10.10.10.13:9000/outpost.goauthentik.io/auth/traefik";
      trustForwardHeader = true;
      maxResponseBodySize = 65536;
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
      { url = "http://10.10.10.13:9000"; }
    ];
  };
}
