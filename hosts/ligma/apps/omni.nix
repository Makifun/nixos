{ config, lib, pkgs, ... }:
let
  base                 = "/ligma/ligma/omni";
  k8sProxyPortExternal = 6443;
  k8sProxyPort         = 8098;
  machineApiPort       = 8091;
  uiPort               = 9999;
  wgPort               = 50180;
  ligmaIP              = "10.10.10.13";
  initialUser          = "makifun@pm.me";
  # renovate: datasource=docker depName=ghcr.io/siderolabs/omni
  omniTag = "v1.7.1";

  # Authentik emits attributes under the Microsoft SOAP claim URIs.
  # Map SAML attribute name → Omni identity field.
  samlAttributeRules = builtins.toJSON {
    "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" = "identity";
    "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"         = "fullname";
  };
in
{
  sops.secrets = {
    omni-account-uuid    = { format = "yaml"; sopsFile = ../secrets.yaml; };
    omni-jwt-signing-key = { format = "yaml"; sopsFile = ../secrets.yaml; };
    # omni-wireguard-key is reserved — Omni currently auto-generates and
    # persists the SideroLink WG private key in its embedded etcd state.
  };

  # Render OMNI_ACCOUNT_ID into a sops env file. Omni does not list env
  # bindings in --help but cobra/viper typically auto-binds OMNI_<FLAG>.
  sops.templates."omni.env" = {
    mode = "0600";
    content = ''
      OMNI_ACCOUNT_ID=${config.sops.placeholder.omni-account-uuid}
    '';
  };

  systemd.tmpfiles.rules = [
    "d '${base}'      0750 root root - -"
    "d '${base}/db'   0750 root root - -"
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
    environmentFiles = [ config.sops.templates."omni.env".path ];
    cmd = [
      "--advertised-api-url=https://omni.makifun.se/"
      "--advertised-kubernetes-proxy-url=https://omni.makifun.se:${toString k8sProxyPortExternal}"
      "--auth-saml-attribute-rules=${samlAttributeRules}"
      "--auth-saml-enabled"
      "--auth-saml-url=https://auth.makifun.se/application/saml/omni/metadata/?download"
      "--bind-addr=0.0.0.0:${toString uiPort}"
      "--cert=/tls/server.crt"
      "--etcd-embedded-db-path=/_out/etcd"
      "--etcd-embedded"
      "--initial-users=${initialUser}"
      "--k8s-proxy-bind-addr=0.0.0.0:${toString k8sProxyPort}"
      "--key=/tls/server.key"
      "--machine-api-advertised-url=grpc://${ligmaIP}:${toString machineApiPort}"
      "--machine-api-bind-addr=0.0.0.0:${toString machineApiPort}"
      "--name=ligma"
      "--private-key-source=file:///keys/jwt.pem"
      "--siderolink-wireguard-advertised-addr=${ligmaIP}:${toString wgPort}"
      "--siderolink-wireguard-bind-addr=${ligmaIP}:${toString wgPort}"
      "--sqlite-storage-path=/_out/db/omni.db"
    ];
    ports = [
      "127.0.0.1:${toString uiPort}:${toString uiPort}"
      "${ligmaIP}:${toString wgPort}:${toString wgPort}/udp"
      "${ligmaIP}:${toString machineApiPort}:${toString machineApiPort}"
      "127.0.0.1:${toString k8sProxyPort}:${toString k8sProxyPort}"
    ];
    volumes = [
      "${base}/etcd:/_out/etcd"
      "${base}/db:/_out/db"
      "${base}/keys:/keys:ro"
      "${base}/tls:/tls:ro"
    ];
  };

  networking.firewall.extraInputRules = ''
    ip saddr 10.10.10.0/24 udp dport ${toString wgPort} accept
    ip saddr 10.10.10.0/24 tcp dport ${toString machineApiPort} accept
    ip saddr 10.10.10.0/24 tcp dport ${toString k8sProxyPortExternal} accept
  '';

  # Traefik — TLS termination + proxy to the container's HTTPS listeners.
  # No Authentik forwardAuth: Omni does its own SAML against Authentik.
  # k8s proxy runs on a dedicated port (6443) on the same hostname so no
  # second-level wildcard cert is needed.
  services.traefik.staticConfigOptions.entryPoints."k8s-proxy".address =
    ":${toString k8sProxyPortExternal}";

  services.traefik.dynamicConfigOptions.http = {
    routers.omni = {
      rule             = "Host(`omni.makifun.se`)";
      entryPoints      = [ "websecure" ];
      service          = "omni-svc";
      tls.certResolver = "letsencrypt";
    };
    routers."omni-k8s-proxy" = {
      rule             = "Host(`omni.makifun.se`)";
      entryPoints      = [ "k8s-proxy" ];
      service          = "omni-k8s-proxy-svc";
      tls.certResolver = "letsencrypt";
    };
    services."omni-svc".loadBalancer = {
      serversTransport = "omni-self-signed";
      servers          = [ { url = "https://127.0.0.1:${toString uiPort}"; } ];
    };
    services."omni-k8s-proxy-svc".loadBalancer = {
      serversTransport = "omni-self-signed";
      servers          = [ { url = "https://127.0.0.1:${toString k8sProxyPort}"; } ];
    };
    serversTransports."omni-self-signed".insecureSkipVerify = true;
  };
}
