{
  config,
  baseFacts,
  hosts,
  lib,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  omniBase = "/${hostname}/${hostname}/omni";
  k8sProxyPortExternal = 6443;
  k8sProxyPort = 8098;
  machineApiPort = 8091;
  uiPort = 9999;
  wgPort = 50180;
  # renovate: datasource=docker depName=ghcr.io/siderolabs/omni
  omniTag = "v1.10.4";
  kmsBase = "/${hostname}/${hostname}/kms";
  kmsPort = 4050;
  # renovate: datasource=docker depName=ghcr.io/siderolabs/kms-server
  kmsTag = "v0.2.0";

  # Authentik emits attributes under the Microsoft SOAP claim URIs.
  # Map SAML attribute name → Omni identity field.
  samlAttributeRules = builtins.toJSON {
    "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress" = "identity";
    "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name" = "fullname";
  };
in
{
  sops.secrets = {
    omni-initial-user = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
    omni-account-uuid = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
    omni-jwt-signing-key = {
      format = "yaml";
      sopsFile = ../secrets.yaml;
    };
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
    "d '${omniBase}'      0750 root root - -"
    "d '${omniBase}/db'   0750 root root - -"
    "d '${omniBase}/etcd' 0750 root root - -"
    "d '${omniBase}/keys' 0750 root root - -"
    "d '${omniBase}/tls'  0750 root root - -"
    "d '${kmsBase}'       0700 root root - -"
  ];

  # Generate a random 32-byte key on first boot.
  # The key persists in zstorage (covered by Backrest S3).
  # Back it up manually before wiping zstorage.
  systemd.services.kms-key-setup = {
    description = "Generate KMS key on first run";
    before = [ "podman-kms.service" ];
    requiredBy = [ "podman-kms.service" ];
    after = [
      "local-fs.target"
      "zfs-mount.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      if [ ! -f ${kmsBase}/kms.key ]; then
        dd if=/dev/urandom bs=32 count=1 2>/dev/null > ${kmsBase}/kms.key
        chmod 400 ${kmsBase}/kms.key
      fi
    '';
  };

  virtualisation.oci-containers.containers.kms = {
    image = "ghcr.io/siderolabs/kms-server:${kmsTag}";
    ports = [ "127.0.0.1:${toString kmsPort}:${toString kmsPort}" ];
    volumes = [ "${kmsBase}:/data:ro" ];
    cmd = [
      "--kms-api-endpoint=0.0.0.0:${toString kmsPort}"
      "--key-path=/data/kms.key"
    ];
  };

  # Stage JWT signing key from sops, generate self-signed TLS for the API
  # listener (Traefik handles the public LE cert; this only protects loopback).
  systemd.services.omni-prep = {
    description = "Prepare Omni keys + self-signed TLS";
    wantedBy = [ "podman-omni.service" ];
    before = [ "podman-omni.service" ];
    after = [
      "local-fs.target"
      "sops-nix.service"
    ];
    path = [
      pkgs.openssl
      pkgs.coreutils
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -m 0640 ${config.sops.secrets.omni-jwt-signing-key.path} ${omniBase}/keys/jwt.pem

      cert=${omniBase}/tls/server.crt
      key=${omniBase}/tls/server.key
      if [ ! -f "$cert" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
          -keyout "$key" -out "$cert" \
          -subj "/CN=omni.${baseFacts.domainName}" \
          -addext "subjectAltName=DNS:omni.${baseFacts.domainName},DNS:localhost,IP:127.0.0.1,IP:${hosts.ligma}"
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
      "--advertised-api-url=https://omni.${baseFacts.domainName}/"
      "--advertised-kubernetes-proxy-url=https://omni.${baseFacts.domainName}:${toString k8sProxyPortExternal}"
      "--auth-saml-attribute-rules=${samlAttributeRules}"
      "--auth-saml-enabled"
      "--auth-saml-url=https://auth.${baseFacts.domainName}/application/saml/omni/metadata/?download"
      "--bind-addr=0.0.0.0:${toString uiPort}"
      "--cert=/tls/server.crt"
      "--etcd-embedded-db-path=/_out/etcd"
      "--etcd-embedded"
      "--initial-users=${config.sops.secrets.omni-initial-user.path}"
      "--k8s-proxy-bind-addr=0.0.0.0:${toString k8sProxyPort}"
      "--key=/tls/server.key"
      "--machine-api-advertised-url=grpc://${hosts.ligma}:${toString machineApiPort}"
      "--machine-api-bind-addr=0.0.0.0:${toString machineApiPort}"
      "--name=${hostname}"
      "--private-key-source=file:///keys/jwt.pem"
      "--siderolink-wireguard-advertised-addr=${hosts.ligma}:${toString wgPort}"
      "--siderolink-wireguard-bind-addr=0.0.0.0:${toString wgPort}"
      "--sqlite-storage-path=/_out/db/omni.db"
    ];
    ports = [
      "127.0.0.1:${toString uiPort}:${toString uiPort}"
      "127.0.0.1:${toString k8sProxyPort}:${toString k8sProxyPort}"
      "${hosts.ligma}:${toString wgPort}:${toString wgPort}/udp"
      "${hosts.ligma}:${toString machineApiPort}:${toString machineApiPort}"
    ];
    volumes = [
      "${omniBase}/etcd:/_out/etcd"
      "${omniBase}/db:/_out/db"
      "${omniBase}/keys:/keys:ro"
      "${omniBase}/tls:/tls:ro"
    ];
  };

  # Omni fetches SAML metadata from Authentik on startup — fail if Authentik isn't up yet.
  # Wait for port 9000 to accept connections before launching the container.
  systemd.services."podman-omni" = {
    after = [ "podman-authentik-server.service" ];
    wants = [ "podman-authentik-server.service" ];
    preStart = ''
      echo "Waiting for Authentik (port 9000)..."
      until ${pkgs.curl}/bin/curl -sf http://127.0.0.1:9000/-/health/live/ > /dev/null 2>&1; do
        sleep 2
      done
    '';
  };

  networking.firewall.extraInputRules = ''
    ip saddr ${hosts.lan} udp dport ${toString wgPort} accept
    ip saddr ${hosts.lan} tcp dport ${toString machineApiPort} accept
    ip saddr ${hosts.lan} tcp dport ${toString k8sProxyPortExternal} accept
  '';

  # Traefik — TLS termination + proxy to the container's HTTPS listeners.
  # No Authentik forwardAuth: Omni does its own SAML against Authentik.
  # k8s proxy runs on a dedicated port (6443) on the same hostname so no
  # second-level wildcard cert is needed.
  services.traefik.staticConfigOptions.entryPoints."k8s-proxy".address =
    ":${toString k8sProxyPortExternal}";

  services.traefik.dynamicConfigOptions.http = {
    middlewares."kms-allowlist".ipAllowList.sourceRange = [ "${hosts.sugma01}/32" ];

    routers.kms = {
      rule = "Host(`kms.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "kms-svc";
      middlewares = [ "kms-allowlist" ];
      tls = {
        certResolver = "letsencrypt";
        domains = [ { main = "*.${baseFacts.domainName}"; } ];
      };
    };

    services."kms-svc".loadBalancer.servers = [
      { url = "h2c://127.0.0.1:${toString kmsPort}"; }
    ];

    routers.omni = {
      rule = "Host(`omni.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "omni-svc";
      tls = {
        certResolver = "letsencrypt";
        domains = [ { main = "*.${baseFacts.domainName}"; } ];
      };
    };
    routers."omni-k8s-proxy" = {
      rule = "Host(`omni.${baseFacts.domainName}`)";
      entryPoints = [ "k8s-proxy" ];
      service = "omni-k8s-proxy-svc";
      tls = {
        certResolver = "letsencrypt";
        domains = [ { main = "*.${baseFacts.domainName}"; } ];
      };
    };
    services."omni-svc".loadBalancer = {
      serversTransport = "omni-self-signed";
      servers = [ { url = "https://127.0.0.1:${toString uiPort}"; } ];
    };
    services."omni-k8s-proxy-svc".loadBalancer = {
      serversTransport = "omni-self-signed";
      servers = [ { url = "https://127.0.0.1:${toString k8sProxyPort}"; } ];
    };
    serversTransports."omni-self-signed".insecureSkipVerify = true;
  };

  ligma.dnsRecords."omni.${baseFacts.domainName}".value = hosts.ligma;
  ligma.dnsRecords."kms.${baseFacts.domainName}".value = hosts.ligma;
}
