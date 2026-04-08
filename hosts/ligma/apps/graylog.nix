{ config, lib, pkgs, ... }:
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
    "d '/ligma/ligma/mongodb'  0755 root root - -"
    "d '/ligma/ligma/datanode' 0755 root root - -"
    "d '${glBase}'            0755 root root - -"
    "d '${glBase}/journal'    0755 root root - -"
    "d '${glBase}/data'       0755 root root - -"
  ];

  # ---------------------------------------------------------------------------
  # Create the isolated podman network shared by all three containers.
  # ---------------------------------------------------------------------------
  systemd.services.podman-create-graylog-network = {
    description    = "Create graylog_network podman network";
    before         = [ "podman-mongodb.service" "podman-datanode.service" "podman-graylog.service" ];
    requiredBy     = [ "podman-mongodb.service" "podman-datanode.service" "podman-graylog.service" ];
    serviceConfig  = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path   = [ pkgs.podman ];
    script = "podman network exists graylog_network || podman network create graylog_network";
  };

  # ---------------------------------------------------------------------------
  # Write env file with SOPS secrets before the containers start.
  # Both graylog and datanode use this file; extra vars are ignored per container.
  # ---------------------------------------------------------------------------
  systemd.services.graylog-env = {
    description    = "Write Graylog environment file from SOPS secrets";
    before         = [ "podman-datanode.service" "podman-graylog.service" ];
    requiredBy     = [ "podman-datanode.service" "podman-graylog.service" ];
    serviceConfig  = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /run/graylog
      chmod 700 /run/graylog
      secret=$(tr -d '\n' < ${config.sops.secrets.graylog-password-secret.path})
      sha2=$(tr -d '\n' < ${config.sops.secrets.graylog-root-password-sha2.path})
      {
        printf 'GRAYLOG_PASSWORD_SECRET=%s\n'              "$secret"
        printf 'GRAYLOG_ROOT_PASSWORD_SHA2=%s\n'           "$sha2"
        printf 'GRAYLOG_DATANODE_PASSWORD_SECRET=%s\n'     "$secret"
        printf 'GRAYLOG_DATANODE_ROOT_PASSWORD_SHA2=%s\n'  "$sha2"
      } > /run/graylog/env
      chmod 400 /run/graylog/env
    '';
  };

  # Enforce env file ordering from the container side as well.
  systemd.services.podman-datanode = {
    after    = [ "graylog-env.service" ];
    requires = [ "graylog-env.service" ];
  };
  systemd.services.podman-graylog = {
    after    = [ "graylog-env.service" ];
    requires = [ "graylog-env.service" ];
  };

  # ---------------------------------------------------------------------------
  # Containers
  # MongoDB and Datanode are only reachable within graylog_network.
  # Graylog publishes its HTTP port to localhost for Traefik.
  # Inter-container hostnames resolved via podman DNS: mongodb, datanode, graylog.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = {

    mongodb = {
      image        = "docker.io/mongo:8";
      volumes      = [ "/ligma/ligma/mongodb:/data/db" ];
      extraOptions = [ "--network=graylog_network" ];
    };

    datanode = {
      image            = "docker.io/graylog/graylog-datanode:7.0";
      environmentFiles = [ "/run/graylog/env" ];
      environment = {
        GRAYLOG_DATANODE_MONGODB_URI  = "mongodb://mongodb/graylog";
        GRAYLOG_DATANODE_NODE_NAME    = "datanode";
        GRAYLOG_DATANODE_ROOT_USERNAME = "admin";
      };
      volumes      = [ "/ligma/ligma/datanode:/var/lib/graylog-datanode" ];
      extraOptions = [ "--network=graylog_network" "--hostname=datanode" ];
    };

    graylog = {
      image            = "docker.io/graylog/graylog:7.0";
      dependsOn        = [ "mongodb" "datanode" ];
      environmentFiles = [ "/run/graylog/env" ];
      environment = {
        GRAYLOG_MONGODB_URI         = "mongodb://mongodb/graylog";
        GRAYLOG_ELASTICSEARCH_HOSTS = "https://datanode:9200";
        GRAYLOG_HTTP_BIND_ADDRESS   = "0.0.0.0:${toString glPort}";
        GRAYLOG_HTTP_EXTERNAL_URI   = "https://graylog.makifun.se/";
      };
      ports   = [ "127.0.0.1:${toString glPort}:${toString glPort}" ];
      volumes = [
        "${glBase}/journal:/usr/share/graylog/data/journal"
        "${glBase}/data:/usr/share/graylog/data/data"
      ];
      extraOptions = [ "--network=graylog_network" ];
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
