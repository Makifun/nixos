{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
in
{
  # traefik_env: |
  #   CF_DNS_API_TOKEN=<token>
  sops.secrets.traefik_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "traefik";
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/traefik";
      user = "traefik";
      group = "traefik";
      mode = "0700";
    }
  ];

  services.traefik = {
    enable = true;
    environmentFiles = [ config.sops.secrets.traefik_env.path ];
  };

  services.traefik.staticConfigOptions = {
    global.sendAnonymousUsage = false;
    log.level = "INFO";
    accessLog.format = "json";

    api = {
      dashboard = true;
      insecure = true;
    };

    entryPoints = {
      traefik = {
        address = "127.0.0.1:8090";
      };
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
        http.tls = {
          certResolver = "letsencrypt";
          domains = [
            {
              main = baseFacts.domainName;
              sans = [
                "*.${baseFacts.domainName}"
              ];
            }
          ];
        };
      };
    };

    certificatesResolvers.letsencrypt.acme = {
      email = "admin@${baseFacts.domainName}";
      storage = "/var/lib/traefik/acme.json";
      keyType = "EC384";
      dnsChallenge = {
        provider = "cloudflare";
        propagation = {
          delayBeforeChecks = "30s";
        };
      };
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      traefik-dashboard = {
        rule = "Host(`traefik-${hostname}.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "api@internal";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      traefik-dashboard-outpost = {
        rule = "Host(`traefik-${hostname}.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    middlewares.authentik.forwardAuth = {
      address = "https://auth.${baseFacts.domainName}/outpost.goauthentik.io/auth/traefik";
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
      { url = "https://auth.${baseFacts.domainName}"; }
    ];
  };

  networking.firewall.extraInputRules = ''
    # OPNsense
    ip saddr ${hosts.lan} tcp dport 80 accept
    ip saddr ${hosts.lan} tcp dport 443 accept
    ip saddr ${hosts.lan} udp dport 443 accept
    # WireGuard
    ip saddr ${hosts.wireguard} tcp dport 80 accept
    ip saddr ${hosts.wireguard} tcp dport 443 accept
    ip saddr ${hosts.wireguard} udp dport 443 accept
  '';

  arrma.dnsRecords."traefik-${hostname}.${baseFacts.domainName}".value = hosts.arrma;
}
