{ config, pkgs, ... }:
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
    listenAddress = "127.0.0.1";
    retentionTime = "30d";
    # Remote_write receiver for Alloy agents (pushed through Traefik).
    extraFlags = [ "--web.enable-remote-write-receiver" ];

    scrapeConfigs = [
      {
        job_name = "rclone";
        static_configs = [{ targets = [ "127.0.0.1:6970" ]; }];
      }
      {
        job_name = "prometheus";
        static_configs = [{ targets = [ "127.0.0.1:9090" ]; }];
      }
      {
        job_name = "distribution";
        metrics_path = "/metrics";
        static_configs = [
          { targets = [ "127.0.0.1:5011" ]; labels = { registry = "dockerhub"; }; }
          { targets = [ "127.0.0.1:5012" ]; labels = { registry = "ghcr";      }; }
          { targets = [ "127.0.0.1:5013" ]; labels = { registry = "lscr";      }; }
          { targets = [ "127.0.0.1:5014" ]; labels = { registry = "quay";      }; }
        ];
      }
      {
        job_name = "loki";
        static_configs = [{ targets = [ "127.0.0.1:3100" ]; }];
      }
      # Alloy agents on all hosts expose their own metrics on :12345.
      # ligma's Alloy is on localhost; other hosts' Alloy is scraped via remote_write.
      {
        job_name = "alloy";
        static_configs = [{ targets = [ "127.0.0.1:12345" ]; }];
      }
      {
        job_name = "opnsense";
        static_configs = [{ targets = [ "opnsense.makifun.se:9100" ]; }];
      }
    ];
  };

  # ---- Grafana ----------------------------------------------------------------
  environment.etc."grafana-dashboards/rclone.json" = {
    source = ../grafana_dashboards/rclone.json;
    mode   = "0444";
  };

  environment.etc."grafana-dashboards/registry.json" = {
    source = ../grafana_dashboards/registry.json;
    mode   = "0444";
  };

  environment.etc."grafana-dashboards/rclone-uptime.json" = {
    source = ../grafana_dashboards/rclone-uptime.json;
    mode   = "0444";
  };

  environment.etc."grafana-dashboards/podman-containers.json" = {
    source = ../grafana_dashboards/podman-containers.json;
    mode   = "0444";
  };

  environment.etc."grafana-dashboards/node-exporter-full.json" = {
    source = ../grafana_dashboards/node-exporter-full.json;
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

  sops.secrets.grafana-admin-password = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
    owner    = "grafana";
  };

  sops.secrets.grafana-gotify-token = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
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
      security.admin_password    = "$__file{${config.sops.secrets.grafana-admin-password.path}}";
      analytics.reporting_enabled = false;
      # Required for Infinity datasource to query localhost URLs (rclone RC API).
      "plugin.yesoreyeram-infinity-datasource".allow_local_mode = true;
    };

    provision = {
      enable = true;
      datasources.settings.datasources = [
        {
          name      = "Prometheus";
          uid       = "prometheus";
          type      = "prometheus";
          url       = "http://127.0.0.1:9090";
          isDefault = true;
          jsonData.timeInterval = "1m";
        }
        {
          name = "Loki";
          uid  = "loki";
          type = "loki";
          url  = "http://127.0.0.1:3100";
        }
        {
          name   = "Infinity";
          uid    = "infinity";
          type   = "yesoreyeram-infinity-datasource";
          access = "proxy";
        }
      ];
      dashboards.settings.providers = [{
        name    = "default";
        options.path = "/etc/grafana-dashboards";
      }];

      alerting = {
        contactPoints.settings.contactPoints = [{
          name = "Gotify";
          receivers = [{
            uid  = "gotify";
            type = "webhook";
            settings = {
              url        = "https://gotify.makifun.se/message?token=\${GOTIFY_TOKEN}";
              httpMethod = "POST";
              # Grafana webhook always sends its own JSON body; `message` sets
              # only the `message` field within that payload. Keep it plain text.
              message = "{{ range .Alerts.Firing }}{{ .Annotations.summary }}\n{{ end }}";
            };
          }];
        }];

        policies.settings.policies = [{
          receiver        = "Gotify";
          group_wait      = "30s";
          group_interval  = "5m";
          repeat_interval = "5m";
        }];

      };
    };
  };

  # systemd reads EnvironmentFile before ExecStartPre, so the env file must
  # exist at service start time. A dedicated setup service writes it first.
  systemd.services.grafana-env-setup = {
    description = "Write Grafana runtime env file from SOPS secrets";
    before      = [ "grafana.service" ];
    requiredBy  = [ "grafana.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      printf 'GOTIFY_TOKEN=%s\n' \
        "$(tr -d '\n' < ${config.sops.secrets.grafana-gotify-token.path})" \
        > /run/grafana-env
      chmod 400 /run/grafana-env
    '';
  };

  # Copy Infinity plugin into Grafana's writable plugins dir before start.
  systemd.services.grafana.serviceConfig =
    let src = pkgs.grafanaPlugins.yesoreyeram-infinity-datasource;
    in {
      ExecStartPre = toString (pkgs.writeShellScript "grafana-install-infinity" ''
        dst=/ligma/ligma/grafana/plugins/yesoreyeram-infinity-datasource
        rm -rf "$dst"
        mkdir -p "$dst"
        cp -r --no-preserve=mode,ownership ${src}/. "$dst/"
        chmod +x "$dst"/gpx_infinity_*
      '');
      EnvironmentFile = "/run/grafana-env";
    };

  # ---- Traefik ----------------------------------------------------------------
  # Grafana handles auth itself via OIDC redirect — no Authentik middleware.
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      grafana = {
        rule        = "Host(`grafana.makifun.se`)";
        entryPoints = [ "websecure" ];
        service     = "grafana-svc";
        tls.certResolver = "letsencrypt";
      };

      # Prometheus — three-router split
      #   priority 30: Authentik outpost callback
      #   priority 10: /api/v1/write — no SSO (Alloy remote_write)
      #   priority  1: everything else — Authentik SSO
      prometheus-outpost = {
        rule        = "Host(`prometheus.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        priority    = 30;
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
      prometheus-write = {
        rule        = "Host(`prometheus.makifun.se`) && PathPrefix(`/api/v1/write`)";
        priority    = 10;
        entryPoints = [ "websecure" ];
        service     = "prometheus-svc";
        tls.certResolver = "letsencrypt";
      };
      prometheus = {
        rule        = "Host(`prometheus.makifun.se`)";
        priority    = 1;
        entryPoints = [ "websecure" ];
        service     = "prometheus-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
    };
    services = {
      "grafana-svc".loadBalancer.servers    = [{ url = "http://127.0.0.1:3000"; }];
      "prometheus-svc".loadBalancer.servers = [{ url = "http://127.0.0.1:9090"; }];
    };
  };
}
