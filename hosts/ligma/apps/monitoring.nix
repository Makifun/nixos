{ config, ... }:
{
  # ---- Prometheus + node_exporter ---------------------------------------------
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/prometheus2";
      user = "prometheus";
      group = "prometheus";
      mode = "0750";
    }
  ];

  services.prometheus = {
    enable = true;
    port = 9090;
    retentionTime = "30d";

    exporters.node = {
      enable = true;
      port = 9100;
      enabledCollectors = [ "systemd" ];
    };

    scrapeConfigs = [
      {
        job_name = "rclone";
        static_configs = [{ targets = [ "127.0.0.1:6969" ]; }];
      }
      {
        job_name = "node";
        static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
      }
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ "127.0.0.1:9090" ]; }];
      }
    ];
  };

  # ---- Grafana ----------------------------------------------------------------
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/grafana' 0700 grafana grafana - -"
  ];

  sops.secrets.grafana-secret-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "grafana";
  };

  services.grafana = {
    enable = true;
    dataDir = "/ligma/ligma/grafana";

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain = "grafana.makifun.se";
        root_url = "https://grafana.makifun.se/";
      };
      # Authentik injects X-authentik-username via Traefik forwardAuth.
      # Grafana trusts it and auto-creates the account on first login.
      "auth.proxy" = {
        enabled = true;
        header_name = "X-authentik-username";
        header_property = "username";
        auto_sign_up = true;
      };
      users.auto_assign_org_role = "Admin";
      security.secret_key = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
      analytics.reporting_enabled = false;
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [{
        name = "Prometheus";
        type = "prometheus";
        url = "http://127.0.0.1:9090";
        isDefault = true;
      }];
    };
  };

  # ---- Traefik ----------------------------------------------------------------
  # Import dashboard ID 13560 from grafana.com for rclone metrics.
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      grafana-outpost = {
        rule        = "Host(`grafana.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority    = 30;
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      grafana = {
        rule        = "Host(`grafana.makifun.se`)";
        priority    = 1;
        entryPoints = [ "websecure" ];
        service     = "grafana-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services."grafana-svc".loadBalancer.servers = [{ url = "http://127.0.0.1:3000"; }];
  };
}
