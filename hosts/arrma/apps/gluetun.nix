{
  baseFacts,
  config,
  hosts,
  ...
}:
{
  sops.secrets.WIREGUARD_ENDPOINT_IP = {
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.WIREGUARD_ENDPOINT_PORT = {
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.WIREGUARD_PUBLIC_KEY = {
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.WIREGUARD_PRIVATE_KEY = {
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.WIREGUARD_PRESHARED_KEY = {
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.WIREGUARD_ADDRESSES = {
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.FIREWALL_VPN_INPUT_PORTS = {
    sopsFile = ../secrets.yaml;
  };

  sops.templates."gluetun.env" = {
    mode = "0400";
    content = ''
      VPN_SERVICE_PROVIDER=custom
      VPN_TYPE=wireguard
      WIREGUARD_ADDRESSES=${config.sops.placeholder.WIREGUARD_ADDRESSES}
      WIREGUARD_ENDPOINT_IP=${config.sops.placeholder.WIREGUARD_ENDPOINT_IP}
      WIREGUARD_ENDPOINT_PORT=${config.sops.placeholder.WIREGUARD_ENDPOINT_PORT}
      WIREGUARD_PRESHARED_KEY=${config.sops.placeholder.WIREGUARD_PRESHARED_KEY}
      WIREGUARD_PRIVATE_KEY=${config.sops.placeholder.WIREGUARD_PRIVATE_KEY}
      WIREGUARD_PUBLIC_KEY=${config.sops.placeholder.WIREGUARD_PUBLIC_KEY}
      FIREWALL_INPUT_PORTS=9090,8192,7474,7476,9696,9697,8000,5656,9707
      FIREWALL_OUTBOUND_SUBNETS=${hosts.lan}
      FIREWALL_VPN_INPUT_PORTS=${config.sops.placeholder.FIREWALL_VPN_INPUT_PORTS}
      DNS_UPSTREAM_RESOLVERS=cloudflare,quad9,google
      BLOCK_MALICIOUS=off
      TZ=${config.time.timeZone}
    '';
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      gluetun = {
        rule = "Host(`gluetun.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "gluetun-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      gluetun-outpost = {
        rule = "Host(`gluetun.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services."gluetun-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:8000"; } ];
  };

  arrma.dnsRecords."gluetun.${baseFacts.domainName}".value = hosts.arrma;

  boot.kernelModules = [ "tun" ];

  networking.firewall.extraInputRules = ''
    tcp dport { 9090, 8192, 7474, 7476, 9697, 8000, 5656, 9707 } ip saddr ${hosts.lan} accept comment "Gluetun input ports"
  '';

  virtualisation.oci-containers.containers.gluetun = {
    # renovate: datasource=docker depName=qmcgaw/gluetun
    image = "qmcgaw/gluetun:v3.41.3";
    environmentFiles = [ config.sops.templates."gluetun.env".path ];
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
}
