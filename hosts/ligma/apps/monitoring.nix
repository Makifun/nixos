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
  environment.etc."grafana-dashboards/rclone.json" = {
    source = ../grafana_dashboards/rclone.json;
    mode   = "0444";
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/grafana' 0700 grafana grafana - -"
  ];

  sops.secrets.grafana-secret-key = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
    owner    = "grafana";
  };

  sops.secrets.grafana-oauth-secret = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
    owner    = "grafana";
  };

  services.grafana = {
    enable = true;
    dataDir = "/ligma/ligma/grafana";

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain    = "grafana.makifun.se";
        root_url  = "https://grafana.makifun.se/";
      };
      # Authentik OIDC — role determined by group membership:
      #   grafana_admin  → Admin
      #   grafana_viewer → Viewer
      "auth.generic_oauth" = {
        enabled             = true;
        name                = "Authentik";
        client_id           = "grafana";
        client_secret       = "$__file{${config.sops.secrets.grafana-oauth-secret.path}}";
        scopes              = "openid profile email groups";
        auth_url            = "https://auth.makifun.se/application/o/authorize/";
        token_url           = "https://auth.makifun.se/application/o/token/";
        api_url             = "https://auth.makifun.se/application/o/userinfo/";
        role_attribute_path = "contains(groups[*], 'grafana_admin') && 'Admin' || contains(groups[*], 'app_admins') && 'Admin' || contains(groups[*], 'grafana_viewer') && 'Viewer' || 'Viewer'";
        allow_sign_up       = true;
        use_pkce            = true;
      };
      users.auto_assign_org_role = "Viewer";
      security.secret_key        = "$__file{${config.sops.secrets.grafana-secret-key.path}}";
      analytics.reporting_enabled = false;
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [{
        name      = "Prometheus";
        type      = "prometheus";
        uid       = "prometheus";
        url       = "http://127.0.0.1:9090";
        isDefault = true;
      }];
      dashboards.settings.providers = [{
        name    = "default";
        options.path = "/etc/grafana-dashboards";
      }];
    };
  };

  # ---- Traefik ----------------------------------------------------------------
  # Grafana handles auth itself via OIDC redirect — no Authentik middleware.
  # Import dashboard ID 13560 from grafana.com for rclone metrics.
  services.traefik.dynamicConfigOptions.http = {
    routers.grafana = {
      rule        = "Host(`grafana.makifun.se`)";
      entryPoints = [ "websecure" ];
      service     = "grafana-svc";
      tls.certResolver = "letsencrypt";
    };
    services."grafana-svc".loadBalancer.servers = [{ url = "http://127.0.0.1:3000"; }];
  };
}
