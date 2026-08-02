{ config, hosts, ... }:
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
      WIREGUARD_ENDPOINT_IP=${config.sops.placeholder.WIREGUARD_ENDPOINT_IP}
      WIREGUARD_ENDPOINT_PORT=${config.sops.placeholder.WIREGUARD_ENDPOINT_PORT}
      WIREGUARD_PUBLIC_KEY=${config.sops.placeholder.WIREGUARD_PUBLIC_KEY}
      WIREGUARD_PRIVATE_KEY=${config.sops.placeholder.WIREGUARD_PRIVATE_KEY}
      WIREGUARD_PRESHARED_KEY=${config.sops.placeholder.WIREGUARD_PRESHARED_KEY}
      WIREGUARD_ADDRESSES=${config.sops.placeholder.WIREGUARD_ADDRESSES}
      BLOCK_MALICIOUS=off
      FIREWALL_INPUT_PORTS=9090,8192,7474,7476,9696,9697,8000,5656,9707
      FIREWALL_VPN_INPUT_PORTS=${config.sops.placeholder.FIREWALL_VPN_INPUT_PORTS}
      FIREWALL_OUTBOUND_SUBNETS=${hosts.lan}
      DNS_UPSTREAM_RESOLVERS=cloudflare,quad9,google
      TZ=Europe/Stockholm
    '';
  };

  boot.kernelModules = [ "tun" ];

  networking.firewall.extraInputRules = ''
    tcp dport { 9090, 8192, 7474, 7476, 9697, 8000, 5656, 9707 } ip saddr ${hosts.lan} accept comment "media via gluetun from LAN"
  '';

  virtualisation.oci-containers.containers.gluetun = {
    # renovate: datasource=docker depName=qmcgaw/gluetun
    image = "qmcgaw/gluetun:v3.41.3";
    environmentFiles = [ config.sops.templates."gluetun.env".path ];
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun:/dev/net/tun"
      "--sysctl=net.ipv6.conf.all.disable_ipv6=1"
      "--add-host=gotify.makifun.se:${hosts.ligma}"
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
