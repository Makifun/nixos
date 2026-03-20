{ config, ... }:
{
  services.pangolin = {
    enable = true;
    baseDomain = "makifun.se";
    # dashboardDomain defaults to "pangolin.makifun.se"
    letsEncryptEmail = "admin@makifun.se";
    dnsProvider = "cloudflare";
    dataDir = "/ligma/ligma/pangolin";
    environmentFile = config.sops.secrets.pangolin_env.path;
    settings.domains.domain1.prefer_wildcard_cert = true;
  };

  # Cloudflare DNS API token for Traefik wildcard cert challenge.
  # Secret file must contain: CF_DNS_API_TOKEN=<token>
  # Token needs Zone:DNS:Edit permission for makifun.se.
  services.traefik.environmentFiles = [ config.sops.secrets.traefik_env.path ];

  # Static routes for NixOS-managed services — declarative, no Pangolin UI needed.
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      forgejo = {
        rule = "Host(`git.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "forgejo";
        tls.certResolver = "letsencrypt";
      };
      authentik = {
        rule = "Host(`auth.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "authentik";
        tls.certResolver = "letsencrypt";
      };
    };
    services = {
      forgejo.loadBalancer.servers = [ { url = "http://127.0.0.1:3000"; } ];
      authentik.loadBalancer.servers = [ { url = "http://127.0.0.1:9000"; } ];
    };
  };

  # Ensure pangolin and traefik start after SOPS secrets are decrypted
  systemd.services.pangolin.after = [ "sops-install-secrets.service" ];
  systemd.services.pangolin.requires = [ "sops-install-secrets.service" ];
  systemd.services.traefik.after = [ "sops-install-secrets.service" ];
  systemd.services.traefik.requires = [ "sops-install-secrets.service" ];

  # Ensure parent directory exists before Pangolin's tmpfiles run
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/pangolin' 0770 pangolin fossorial - -"
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
