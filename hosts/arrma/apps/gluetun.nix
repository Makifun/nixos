{
  baseFacts,
  config,
  hosts,
  ...
}:
{
  # gluetun_env: |
  #   WIREGUARD_ADDRESSES=<cidr>
  #   WIREGUARD_ENDPOINT_IP=<ip>
  #   WIREGUARD_ENDPOINT_PORT=<port>
  #   WIREGUARD_PRESHARED_KEY=<key>
  #   WIREGUARD_PRIVATE_KEY=<key>
  #   WIREGUARD_PUBLIC_KEY=<key>
  #   FIREWALL_VPN_INPUT_PORTS=<port>
  sops.secrets.gluetun_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  boot.kernelModules = [ "tun" ];

  virtualisation.oci-containers.containers.gluetun = {
    # renovate: datasource=docker depName=qmcgaw/gluetun
    image = "docker.io/qmcgaw/gluetun:v3.41.3";
    environmentFiles = [ config.sops.secrets.gluetun_env.path ];
    environment = {
      VPN_SERVICE_PROVIDER = "custom";
      VPN_TYPE = "wireguard";
      FIREWALL_INPUT_PORTS = "9090,8192,7474,7476,9697,8000,5656,9707";
      FIREWALL_OUTBOUND_SUBNETS = hosts.lan;
      DNS_UPSTREAM_RESOLVERS = "cloudflare,quad9,google";
      BLOCK_MALICIOUS = "off";
      TZ = config.time.timeZone;
    };
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun:/dev/net/tun"
      "--sysctl=net.ipv6.conf.all.disable_ipv6=1"
      "--add-host=gotify.${baseFacts.domainName}:${hosts.ligma}"
      "--add-host=sonarrpg.${baseFacts.domainName}:${hosts.sugmaGW}"
      "--add-host=sonarr4kpg.${baseFacts.domainName}:${hosts.sugmaGW}"
      "--add-host=radarrpg.${baseFacts.domainName}:${hosts.sugmaGW}"
      "--add-host=radarr4kpg.${baseFacts.domainName}:${hosts.sugmaGW}"
    ];
    ports = [
      "9090:9090"
      "8192:8192"
      "7474:7474"
      "7476:7476"
      "9697:9697"
      "8000:8000"
      "5656:5656"
      "9707:9707"
    ];
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      gluetun = {
        rule = "Host(`gluetun.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "gluetun-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      gluetun-outpost = {
        rule = "Host(`gluetun.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services."gluetun-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:8000"; } ];
  };

  networking.firewall.extraInputRules = ''
    tcp dport { 9090, 8192, 7474, 7476, 9697, 8000, 5656, 9707 } ip saddr ${hosts.lan} accept comment "Gluetun input ports"
  '';

  arrma.dnsRecords."gluetun.${baseFacts.domainName}".value = hosts.arrma;
}
