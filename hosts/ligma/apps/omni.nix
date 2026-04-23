{ config, lib, pkgs, ... }:
let
  base        = "/ligma/ligma/omni";
  uiPort      = 9999;
  wgPort      = 50180;
  ligmaIP     = "10.10.10.13";
  initialUser = "makifun@pm.me";
  # renovate: datasource=docker depName=ghcr.io/siderolabs/omni
  omniTag = "v1.7.0";
in
{
  sops.secrets = {
    omni-account-uuid    = { format = "yaml"; sopsFile = ../secrets.yaml; };
    omni-jwt-signing-key = { format = "yaml"; sopsFile = ../secrets.yaml; };
    # omni-wireguard-key is reserved — Omni currently auto-generates and
    # persists the SideroLink WG private key in its embedded etcd state.
  };

  # Account ID rendered into a YAML config (Omni's --config-path accepts
  # cobra/viper config files). Distroless image has no shell so we can't
  # wrap, and Omni does not bind env vars to its flags.
  sops.templates."omni-config.yaml" = {
    mode = "0600";
    content = ''
      account-id: "${config.sops.placeholder.omni-account-uuid}"
    '';
  };

  systemd.tmpfiles.rules = [
    "d '${base}'      0750 root root - -"
    "d '${base}/etcd' 0750 root root - -"
    "d '${base}/keys' 0750 root root - -"
    "d '${base}/tls'  0750 root root - -"
  ];

  # Stage JWT signing key from sops, generate self-signed TLS for the API
  # listener (Traefik handles the public LE cert; this only protects loopback).
  systemd.services.omni-prep = {
    description = "Prepare Omni keys + self-signed TLS";
    wantedBy    = [ "podman-omni.service" ];
    before      = [ "podman-omni.service" ];
    after       = [ "local-fs.target" "sops-nix.service" ];
    path        = [ pkgs.openssl pkgs.coreutils ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -m 0640 ${config.sops.secrets.omni-jwt-signing-key.path} ${base}/keys/jwt.pem

      cert=${base}/tls/server.crt
      key=${base}/tls/server.key
      if [ ! -f "$cert" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
          -keyout "$key" -out "$cert" \
          -subj "/CN=omni.makifun.se" \
          -addext "subjectAltName=DNS:omni.makifun.se,DNS:localhost,IP:127.0.0.1,IP:${ligmaIP}"
        chmod 0640 "$key" "$cert"
      fi
    '';
  };

  virtualisation.oci-containers.containers.omni = {
    image = "ghcr.io/siderolabs/omni:${omniTag}";
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--device=/dev/net/tun"
    ];
    cmd = [
      "--config-path=/config/omni.yaml"
      "--name=ligma"
      "--bind-addr=0.0.0.0:${toString uiPort}"
      "--cert=/tls/server.crt"
      "--key=/tls/server.key"
      "--private-key-source=file:///keys/jwt.pem"
      "--advertised-api-url=https://omni.makifun.se/"
      "--siderolink-wireguard-advertised-addr=${ligmaIP}:${toString wgPort}"
      "--siderolink-wireguard-bind-addr=0.0.0.0:${toString wgPort}"
      "--etcd-embedded"
      "--etcd-embedded-db-path=/_out/etcd"
      "--auth-saml-enabled"
      "--auth-saml-metadata=https://auth.makifun.se/application/saml/omni/metadata/?download"
      "--initial-users=${initialUser}"
    ];
    ports = [
      "127.0.0.1:${toString uiPort}:${toString uiPort}"
      "${ligmaIP}:${toString wgPort}:${toString wgPort}/udp"
    ];
    volumes = [
      "${base}/etcd:/_out/etcd"
      "${base}/keys:/keys:ro"
      "${base}/tls:/tls:ro"
      "${config.sops.templates."omni-config.yaml".path}:/config/omni.yaml:ro"
    ];
  };

  # SideroLink UDP — accept only from the LAN subnet.
  networking.firewall.extraInputRules = ''
    ip saddr 10.10.10.0/24 udp dport ${toString wgPort} accept
  '';

  # Traefik — TLS termination + proxy to the container's HTTPS listener.
  # No Authentik forwardAuth: Omni does its own SAML against Authentik.
  services.traefik.dynamicConfigOptions.http = {
    routers.omni = {
      rule             = "Host(`omni.makifun.se`)";
      entryPoints      = [ "websecure" ];
      service          = "omni-svc";
      tls.certResolver = "letsencrypt";
    };
    services."omni-svc".loadBalancer = {
      serversTransport = "omni-self-signed";
      servers          = [ { url = "https://127.0.0.1:${toString uiPort}"; } ];
    };
    serversTransports."omni-self-signed".insecureSkipVerify = true;
  };
}
