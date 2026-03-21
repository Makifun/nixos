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

    domains.makifun = {
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
      ports = [
        "127.0.0.1:3000:3000" # Express API + WebSocket server
        "127.0.0.1:3001:3001" # External API (Traefik HTTP provider, gerbil)
        "127.0.0.1:3002:3002" # Next.js frontend
      ];
      environmentFiles = [ config.sops.secrets.pangolin_env.path ];
    };

    gerbil = {
      image = "fosrl/gerbil:1.3.0";
      dependsOn = [ "pangolin" ];
      cmd = [
        "--reachableAt"
        "http://gerbil:3004"
        "--generateAndSaveKeyTo"
        "/var/config/peer_key"
        "--remoteConfig"
        "http://pangolin:3001/api/v1"
      ];
      volumes = [ "/ligma/ligma/pangolin/config:/var/config" ];
      extraOptions = [
        "--network=host"
        "--cap-add=NET_ADMIN"
        "--cap-add=SYS_MODULE"
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

  # Required for WireGuard routing — gerbil uses --network=host so these
  # must be set on the host, not as container --sysctl flags.
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv4.conf.all.src_valid_mark" = 1;
  };

  # Gerbil runs with --network=host and uses the host /etc/hosts.
  # "pangolin" must resolve so the Host header matches what Pangolin's
  # CSRF protection expects (matching the original Docker container name).
  networking.extraHosts = "127.0.0.1 pangolin";

  networking = {
    hostName = "ligma";
    useDHCP = true;
    hostId = "324bbd6b";
    firewall.allowedTCPPorts = [
      80
      443
    ];
    firewall.allowedUDPPorts = [
      443
      51820
    ];
  };
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/pangolin' 0755 root root - -"
    "d '/ligma/ligma/pangolin/config' 0755 root root - -"
  ];

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      # Next.js frontend — handles everything except /api/v1
      pangolin-next = {
        rule = "Host(`pangolin.makifun.se`) && !PathPrefix(`/api/v1`)";
        entryPoints = [ "websecure" ];
        service = "pangolin-next";
        tls.certResolver = "letsencrypt";
      };
      # Express API server
      pangolin-api = {
        rule = "Host(`pangolin.makifun.se`) && PathPrefix(`/api/v1`)";
        entryPoints = [ "websecure" ];
        service = "pangolin-api";
        tls.certResolver = "letsencrypt";
      };
      # WebSocket fallback (lower priority due to shorter rule)
      pangolin-ws = {
        rule = "Host(`pangolin.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "pangolin-api";
        tls.certResolver = "letsencrypt";
      };
    };
    services = {
      pangolin-next.loadBalancer.servers = [ { url = "http://127.0.0.1:3002"; } ];
      pangolin-api.loadBalancer.servers = [ { url = "http://127.0.0.1:3000"; } ];
    };
  };

  # Pangolin server secret (SERVER_SECRET=<random>)
  sops.secrets.pangolin_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
}
