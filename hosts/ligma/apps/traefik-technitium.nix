{ baseFacts, hosts, ... }:
let
  technitiumPort = 53443;
in
{
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      technitium = {
        rule = "Host(`technitium.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "technitium-svc";
        tls.certResolver = "letsencrypt";
      };
      doh = {
        rule = "Host(`doh.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "doh-svc";
        tls.certResolver = "letsencrypt";
      };
    };
    services = {
      technitium-svc.loadBalancer = {
        servers = [ { url = "https://${hosts.technitium}:${toString technitiumPort}"; } ];
        serversTransport = "technitium-transport";
      };
      doh-svc.loadBalancer.servers = [ { url = "http://${hosts.technitium}"; } ];
    };
    serversTransports."technitium-transport".insecureSkipVerify = true;
  };

  ligma.dnsRecords."technitium.${baseFacts.domainName}".value = hosts.ligma;
  ligma.dnsRecords."doh.${baseFacts.domainName}".value = hosts.ligma;
}
