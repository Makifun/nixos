{ config, lib, pkgs, ... }:
let
  glBase    = "/ligma/ligma/graylog";
  glPort    = 9099;  # 9000 is taken by the Authentik embedded outpost
in
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "graylog_6.0"
  ];
  # ---------------------------------------------------------------------------
  # Secrets
  # Generate and add to secrets.yaml:
  #   graylog-password-secret: "<output of: pwgen -N1 -s 96>"
  #   graylog-root-password-sha2: "<output of: echo -n 'yourpassword' | sha256sum | cut -d' ' -f1>"
  # ---------------------------------------------------------------------------
  sops.secrets.graylog-password-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner   = "graylog";
  };
  sops.secrets.graylog-root-password-sha2 = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner   = "graylog";
  };

  # ---------------------------------------------------------------------------
  # MongoDB — run as a Podman container to avoid building the unfree package.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers.mongodb = {
    image = "docker.io/mongo:7";
    volumes = [ "${glBase}/mongodb:/data/db" ];
    ports  = [ "127.0.0.1:27017:27017" ];
    extraOptions = [ "--network=host" ];
  };

  systemd.tmpfiles.rules = [
    "d '${glBase}'            0755 root       root       - -"
    "d '${glBase}/mongodb'    0700 root       root       - -"
    "d '${glBase}/opensearch' 0700 opensearch opensearch - -"
    "d '${glBase}/journal'    0750 graylog    graylog    - -"
    "d '${glBase}/data'       0750 graylog    graylog    - -"
  ];

  # ---------------------------------------------------------------------------
  # OpenSearch — log data store (Graylog 6.x requires OpenSearch 2.x)
  # ---------------------------------------------------------------------------
  services.opensearch = {
    enable  = true;
    dataDir = "${glBase}/opensearch";
    settings = {
      "cluster.name"             = "graylog";
      "network.host"             = "127.0.0.1";
      "discovery.type"           = "single-node";
      "action.auto_create_index" = false;
    };
    # Keep heap small on a homelab VM; adjust if you ingest heavily.
    extraJavaOptions = [ "-Xms512m" "-Xmx512m" ];
  };

  # ---------------------------------------------------------------------------
  # Graylog
  # The NixOS module writes passwordSecret/rootPasswordSha2 directly into a
  # nix-store config file.  To keep secrets out of the store we:
  #   1. Set syntactically-valid placeholder values (never actually read).
  #   2. Override GRAYLOG_CONF to point to /run/graylog/graylog.conf.
  #   3. Generate that file in preStart with the real values from SOPS.
  # ---------------------------------------------------------------------------
  services.graylog = {
    enable = true;
    # Placeholders — real values injected at runtime (see preStart below).
    passwordSecret  = "PLACEHOLDER_INJECTED_BY_SOPS_AT_RUNTIME_DO_NOT_USE_0000000000000000";
    rootPasswordSha2 = "0000000000000000000000000000000000000000000000000000000000000000";

    elasticsearchHosts = [ "http://127.0.0.1:9200" ];
    mongodbUri         = "mongodb://127.0.0.1/graylog";
    messageJournalDir  = "${glBase}/journal";
    dataDir            = "${glBase}/data";
    nodeIdFile         = "${glBase}/node-id";  # persist node identity across reboots

    extraConfig = ''
      http_bind_address = 127.0.0.1:${toString glPort}
    '';
  };

  systemd.services.graylog = {
    after    = [ "podman-mongodb.service" "opensearch.service" ];
    requires = [ "podman-mongodb.service" "opensearch.service" ];
    serviceConfig = {
      RuntimeDirectory     = "graylog";
      RuntimeDirectoryMode = "0700";
    };
    # Point Graylog at the runtime config (not the nix-store one).
    environment.GRAYLOG_CONF = lib.mkForce "/run/graylog/graylog.conf";
    # Append AFTER the module's own preStart (plugin setup).
    preStart = lib.mkAfter ''
      # Write graylog.conf with SOPS secrets injected at runtime.
      {
        echo "is_master = true"
        echo "node_id_file = ${glBase}/node-id"
        echo "password_secret = $(tr -d '\n' < ${config.sops.secrets.graylog-password-secret.path})"
        echo "root_username = admin"
        echo "root_password_sha2 = $(tr -d '\n' < ${config.sops.secrets.graylog-root-password-sha2.path})"
        echo "elasticsearch_hosts = http://127.0.0.1:9200"
        echo "message_journal_dir = ${glBase}/journal"
        echo "mongodb_uri = mongodb://127.0.0.1/graylog"
        echo "plugin_dir = /var/lib/graylog/plugins"
        echo "data_dir = ${glBase}/data"
        echo "http_bind_address = 127.0.0.1:${toString glPort}"
      } > /run/graylog/graylog.conf
      chmod 400 /run/graylog/graylog.conf
    '';
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
