{ config, pkgs, ... }:
let
  pangolinConfig = (pkgs.formats.yaml { }).generate "config.yml" {
    app = {
      dashboard_url = "https://pangolin.makifun.se";
      log_failed_attempts = true;
      log_level = "info";
      save_logs = true;
      telemetry = {
        anonymous_usage = false;
      };
    };

    server = {
      external_port = 3001;
      internal_port = 3000;
      next_port = 3002;
      base_domain = "makifun.se";
    };

    domains.makifun.se = {
      base_domain = "makifun.se";
      cert_resolver = "letsencrypt";
      prefer_wildcard_cert = true;
      lets_encrypt_email = "admin@makifun.se";
    };

    gerbil = {
      start_port = 51820;
      base_endpoint = "pangolin.makifun.se";
      dns_provider = "cloudflare";
    };

    flags = {
      require_email_verification = false;
      disable_signup_without_invite = true;
      disable_user_create_org = true;
      allow_raw_resources = true;
      enable_integration_api = false;
    };
  };
in
{
  virtualisation.oci-containers.backend = "podman";

  virtualisation.oci-containers.containers = {
    pangolin = {
      image = "fosrl/pangolin:1.16.2";
      volumes = [ "/ligma/ligma/pangolin/config:/app/config" ];
      ports = [ "127.0.0.1:3000:3000" ];
      environmentFiles = [ config.sops.secrets.pangolin_env.path ];
    };

    gerbil = {
      image = "fosrl/gerbil:1.3.0";
      dependsOn = [ "pangolin" ];
      cmd = [
        "--reachableAt"
        "http://gerbil:3003"
        "--generateAndSaveKeyTo"
        "/var/config/peer_key"
        "--remoteConfig"
        "http://pangolin:3001/api/v1"
      ];
      volumes = [ "/ligma/ligma/pangolin/config:/var/config" ];
      ports = [ "51820:51820/udp" ];
      extraOptions = [
        "--network=host"
        "--cap-add=NET_ADMIN"
        "--cap-add=SYS_MODULE"
        "--sysctl=net.ipv4.ip_forward=1"
        "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
      ];
    };
  };

  # Write config.yml only if it doesn't already exist, so manual edits are preserved.
  systemd.services.pangolin-config-init = {
    description = "Initialise Pangolin config.yml";
    wantedBy = [ "podman-pangolin.service" ];
    before = [ "podman-pangolin.service" ];
    serviceConfig.Type = "oneshot";
    script = ''
      if [ ! -f /ligma/ligma/pangolin/config/config.yml ]; then
        cp ${pangolinConfig} /ligma/ligma/pangolin/config/config.yml
        chmod 600 /ligma/ligma/pangolin/config/config.yml
      fi
    '';
  };

  # WireGuard port for gerbil tunnels
  networking.firewall.allowedUDPPorts = [
    443
    51820
  ];

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/pangolin' 0755 root root - -"
    "d '/ligma/ligma/pangolin/config' 0755 root root - -"
  ];

  services.traefik.enable = true;

  # Cloudflare DNS API token for Traefik wildcard cert challenge.
  # Secret file must contain: CF_DNS_API_TOKEN=<token>
  # Token needs Zone:DNS:Edit permission for makifun.se.
  services.traefik.environmentFiles = [ config.sops.secrets.traefik_env.path ];

  services.traefik.staticConfigOptions = {
    global.sendAnonymousUsage = false;
    certificatesResolvers.letsencrypt.acme = {
      email = "admin@makifun.se";
      keyType = "EC384";
      dnsChallenge = {
        provider = "cloudflare";
        propagation = {
          delayBeforeChecks = "30s";
          disableChecks = true;
        };
      };
    };
    # HTTP/3 (QUIC) on port 443 — requires UDP 443 open in firewall
    entryPoints.websecure.http3.advertisedPort = 443;
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.pangolin = {
      rule = "Host(`pangolin.makifun.se`)";
      entryPoints = [ "websecure" ];
      service = "pangolin";
      tls.certResolver = "letsencrypt";
    };
    services.pangolin.loadBalancer.servers = [ { url = "http://127.0.0.1:3000"; } ];
  };

  # Pangolin server secret (SERVER_SECRET=<random>)
  sops.secrets.pangolin_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Traefik Cloudflare token (CF_DNS_API_TOKEN=<token>)
  sops.secrets.traefik_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "traefik";
  };
}
