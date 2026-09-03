{
  config,
  baseFacts,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  beszelPort = 8095;
  beszelBase = "/${hostname}/${hostname}/beszel";
  # renovate: datasource=docker depName=henrygd/beszel
  beszelTag = "0.19.0";
in
{
  sops.secrets.beszel_heartbeat_url = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  systemd.tmpfiles.rules = [
    "d '${beszelBase}/data' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel = {
    image = "docker.io/henrygd/beszel:${beszelTag}";
    ports = [ "127.0.0.1:${toString beszelPort}:8090" ];
    environment = {
      # OIDC login verified working — require it, no local password fallback.
      DISABLE_PASSWORD_AUTH = "true";
    };
    environmentFiles = [ config.sops.secrets.beszel_heartbeat_url.path ];
    volumes = [ "${beszelBase}/data:/beszel_data" ];
  };

  # No Authentik forwardAuth middleware — Beszel handles its own login via
  # native OIDC (beszel.tf in the authentik repo), same migration Gotify
  # went through. No outpost-callback router needed either.
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      beszel = {
        rule = "Host(`beszel.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "beszel-svc";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."beszel-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString beszelPort}"; }
    ];
  };

  ligma.dnsRecords."beszel.${baseFacts.domainName}".value = hosts.ligma;
}
