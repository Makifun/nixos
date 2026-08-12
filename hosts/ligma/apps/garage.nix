{
  config,
  hosts,
  baseFacts,
  ...
}:
let
  # renovate: datasource=docker depName=dxflrs/garage
  garageTag = "v2.3.0";
  garageS3Port = 3900;
  garageMetaDir = "/ligma/garage/meta";
  garageDataDir = "/ligma/garage/data";
in
{
  sops.secrets.garage-rpc-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.garage-admin-token = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.templates."garage.toml" = {
    content = ''
      metadata_dir = "/var/lib/garage/meta"
      data_dir = "/var/lib/garage/data"
      db_engine = "lmdb"
      replication_factor = 1

      rpc_secret = "${config.sops.placeholder.garage-rpc-secret}"
      rpc_bind_addr = "0.0.0.0:3902"
      rpc_public_addr = "127.0.0.1:3902"

      [admin]
      api_bind_addr = "127.0.0.1:3901"
      admin_token = "${config.sops.placeholder.garage-admin-token}"

      [s3_api]
      s3_region = "garage"
      api_bind_addr = "0.0.0.0:${toString garageS3Port}"
    '';
  };

  systemd.tmpfiles.rules = [
    "d '${garageMetaDir}' 0750 root root - -"
    "d '${garageDataDir}' 0750 root root - -"
  ];

  # Mount the sops-rendered config — start after sops-nix so the file exists.
  systemd.services.podman-garage = {
    after = [ "sops-nix.service" ];
    wants = [ "sops-nix.service" ];
  };

  virtualisation.oci-containers.containers.garage = {
    image = "docker.io/dxflrs/garage:${garageTag}";
    ports = [
      "127.0.0.1:${toString garageS3Port}:${toString garageS3Port}"
      "127.0.0.1:3901:3901"
      "127.0.0.1:3902:3902"
    ];
    volumes = [
      "${config.sops.templates."garage.toml".path}:/etc/garage.toml:ro"
      "${garageMetaDir}:/var/lib/garage/meta"
      "${garageDataDir}:/var/lib/garage/data"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.garage-s3 = {
      rule = "Host(`s3.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "garage-s3-svc";
      # No Authentik — S3 clients authenticate with access keys.
      tls = {
        certResolver = "letsencrypt";
        domains = [ { main = "*.${baseFacts.domainName}"; } ];
      };
    };
    services."garage-s3-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString garageS3Port}"; }
    ];
  };

  ligma.dnsRecords."s3.${baseFacts.domainName}".value = hosts.ligma;
}
