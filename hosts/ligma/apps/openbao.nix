{
  baseFacts,
  config,
  hosts,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  openbaoPort = 8200;
  openbaoBase = "/${hostname}/${hostname}/openbao";
  # renovate: datasource=docker depName=quay.io/openbao/openbao
  openbaoTag = "2.7.1";

  # The image runs as openbao (100:1000) and never as root.
  openbaoUid = 100;
  openbaoGid = 1000;

  openbaoConfig = pkgs.writeText "openbao.hcl" ''
    ui            = true
    disable_mlock = true
    api_addr      = "https://openbao.${baseFacts.domainName}"
    cluster_addr  = "https://127.0.0.1:8201"

    listener "tcp" {
      address     = "0.0.0.0:8200"
      tls_disable = true
    }

    storage "raft" {
      path    = "/openbao/file"
      node_id = "${hostname}"
    }

    seal "static" {
      current_key_id = "ligma-1"
      current_key    = "file:///openbao/secrets/unseal.key"
    }
  '';
in
{
  # openbao-unseal-key: <openssl rand -hex 32>
  sops.secrets.openbao-unseal-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    uid = openbaoUid;
    gid = openbaoGid;
    mode = "0400";
  };

  systemd.tmpfiles.rules = [
    "d '${openbaoBase}'      0750 root          root          - -"
    "d '${openbaoBase}/data' 0700 ${toString openbaoUid} ${toString openbaoGid} - -"
  ];

  virtualisation.oci-containers.containers.openbao = {
    image = "quay.io/openbao/openbao:${openbaoTag}";
    cmd = [ "server" ];
    ports = [ "127.0.0.1:${toString openbaoPort}:8200" ];
    volumes = [
      "${openbaoConfig}:/openbao/config/config.hcl:ro"
      "${config.sops.secrets.openbao-unseal-key.path}:/openbao/secrets/unseal.key:ro"
      "${openbaoBase}/data:/openbao/file"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.openbao = {
      rule = "Host(`openbao.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "openbao";
      tls = {
        certResolver = "letsencrypt";
        domains = [ { main = "*.${baseFacts.domainName}"; } ];
      };
    };
    services.openbao.loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString openbaoPort}"; }
    ];
  };

  ligma.dnsRecords."openbao.${baseFacts.domainName}".value = hosts.ligma;
}
