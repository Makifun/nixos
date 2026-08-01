{ baseFacts, ... }:
let
  beszelPort = 8095;
  beszelBase = "/ligma/ligma/beszel";
  # renovate: datasource=docker depName=henrygd/beszel
  beszelTag = "0.18.7";
in
{
  systemd.tmpfiles.rules = [
    "d '${beszelBase}/data' 0755 root root - -"
  ];

  virtualisation.oci-containers.containers.beszel = {
    image = "henrygd/beszel:${beszelTag}";
    ports = [ "127.0.0.1:${toString beszelPort}:8090" ];
    volumes = [ "${beszelBase}/data:/beszel_data" ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      beszel = {
        rule = "Host(`beszel.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "beszel-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      beszel-outpost = {
        rule = "Host(`beszel.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."beszel-svc".loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString beszelPort}"; }
    ];
  };

  ligma.dnsRecords."beszel.${baseFacts.domainName}".value = "10.10.10.13";
}
