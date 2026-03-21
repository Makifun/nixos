{ config, ... }:
{
  services.pangolin = {
    enable = true;
    baseDomain = "makifun.se";
    letsEncryptEmail = "admin@makifun.se";
    dnsProvider = "cloudflare";
    dataDir = "/ligma/ligma/pangolin";
    environmentFile = config.sops.secrets.pangolin_env.path;
    settings.domains.domain1.prefer_wildcard_cert = true;
    settings.flags.enable_integration_api = true;
  };

  # Cloudflare DNS API token for Traefik wildcard cert challenge.
  # Secret file must contain: CF_DNS_API_TOKEN=<token>
  # Token needs Zone:DNS:Edit permission for makifun.se.
  services.traefik.environmentFiles = [ config.sops.secrets.traefik_env.path ];

  services.traefik.staticConfigOptions = {
    global.sendAnonymousUsage = false;
    certificatesResolvers.letsencrypt.acme = {
      keyType = "EC384";
      dnsChallenge.propagation = {
        delayBeforeChecks = "30s";
        disableChecks = true;
      };
    };
    # HTTP/3 (QUIC) on port 443 — requires UDP 443 open in firewall
    entryPoints.websecure.http3.advertisedPort = 443;
  };

  # UDP 443 for HTTP/3
  networking.firewall.allowedUDPPorts = [ 443 ];

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/pangolin' 0770 pangolin fossorial - -"
    # gerbil-wg0-fix-script has a hardcoded /var/lib/pangolin path (module bug)
    "d '/var/lib/pangolin' 0770 pangolin fossorial - -"
    "d '/var/lib/pangolin/config' 0770 pangolin fossorial - -"
  ];

  # Pangolin server secret (SERVER_SECRET=<random>)
  sops.secrets.pangolin_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "pangolin";
  };

  # Traefik Cloudflare token (CF_DNS_API_TOKEN=<token>)
  sops.secrets.traefik_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "traefik";
  };
}
