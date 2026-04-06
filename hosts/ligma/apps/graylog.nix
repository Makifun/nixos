{ config, lib, ... }:
let
  glBase = "/ligma/ligma/graylog";
  glPort = 9099;  # 9000 is taken by the Authentik embedded outpost
in
{
  # ---------------------------------------------------------------------------
  # Secrets
  # Generate and add to secrets.yaml:
  #   graylog-password-secret: "<output of: pwgen -N1 -s 96>"
  #   graylog-root-password-sha2: "<output of: echo -n 'yourpassword' | sha256sum | cut -d' ' -f1>"
  # ---------------------------------------------------------------------------
  sops.secrets.graylog-password-secret = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.graylog-root-password-sha2 = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/mongodb'    0755 root root - -"
    "d '/ligma/ligma/opensearch' 0755 root root - -"
    "d '${glBase}'              0755 root root - -"
    "d '${glBase}/journal'      0755 root root - -"
    "d '${glBase}/data'         0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Write env file with SOPS secrets before the Graylog container starts.
  # ---------------------------------------------------------------------------
  systemd.services.graylog-env = {
    description    = "Write Graylog environment file from SOPS secrets";
    before         = [ "podman-graylog.service" ];
    requiredBy     = [ "podman-graylog.service" ];
    serviceConfig  = {
      Type              = "oneshot";
      RemainAfterExit   = true;
      RuntimeDirectory  = "graylog";
      RuntimeDirectoryMode = "0700";
    };
    script = ''
      printf 'GRAYLOG_PASSWORD_SECRET=%s\n'    "$(tr -d '\n' < ${config.sops.secrets.graylog-password-secret.path})"    >  /run/graylog/env
      printf 'GRAYLOG_ROOT_PASSWORD_SHA2=%s\n' "$(tr -d '\n' < ${config.sops.secrets.graylog-root-password-sha2.path})" >> /run/graylog/env
      chmod 400 /run/graylog/env
    '';
  };

  # ---------------------------------------------------------------------------
  # Containers — all use host networking so they talk via 127.0.0.1.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = {

    mongodb = {
      image   = "docker.io/mongo:7";
      volumes = [ "/ligma/ligma/mongodb:/data/db" ];
      extraOptions = [ "--network=host" ];
    };

    opensearch = {
      image   = "docker.io/opensearchproject/opensearch:2";
      volumes = [ "/ligma/ligma/opensearch:/usr/share/opensearch/data" ];
      environment = {
        "cluster.name"             = "graylog";
        "discovery.type"           = "single-node";
        "action.auto_create_index" = "false";
        "network.host"             = "127.0.0.1";
        "OPENSEARCH_JAVA_OPTS"     = "-Xms512m -Xmx512m";
        "DISABLE_SECURITY_PLUGIN"  = "true";
      };
      extraOptions = [ "--network=host" ];
    };

    graylog = {
      image            = "docker.io/graylog/graylog:7.0";
      dependsOn        = [ "mongodb" "opensearch" ];
      environmentFiles = [ "/run/graylog/env" ];
      environment = {
        GRAYLOG_MONGODB_URI          = "mongodb://127.0.0.1/graylog";
        GRAYLOG_ELASTICSEARCH_HOSTS  = "http://127.0.0.1:9200";
        GRAYLOG_HTTP_BIND_ADDRESS    = "0.0.0.0:${toString glPort}";
        GRAYLOG_HTTP_EXTERNAL_URI    = "https://graylog.makifun.se/";
      };
      volumes = [
        "${glBase}/journal:/usr/share/graylog/data/journal"
        "${glBase}/data:/usr/share/graylog/data/data"
      ];
      extraOptions = [ "--network=host" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Traefik
  # No authentik middleware — Graylog has its own authentication.
  # Added to Authentik ligma_apps (apps.tf) for the app-panel link only.
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers.graylog = {
      rule        = "Host(`graylog.makifun.se`)";
      entryPoints = [ "websecure" ];
      service     = "graylog-svc";
      tls.certResolver = "letsencrypt";
    };
    services.graylog-svc.loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString glPort}"; }
    ];
  };
}
