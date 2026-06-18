{
  config,
  lib,
  pkgs,
  ...
}:
let
  # renovate: datasource=docker depName=netbirdio/management
  managementTag = "0.72.4";
  # renovate: datasource=docker depName=netbirdio/signal
  signalTag = "0.72.4";
  # renovate: datasource=docker depName=netbirdio/relay
  relayTag = "0.73.0";
  # renovate: datasource=docker depName=netbirdio/dashboard
  dashboardTag = "v2.39.0";

  base = "/ligma/ligma/netbird";
  domain = "netbird.makifun.se";
  clientId = "netbird";

  # Authentik OIDC endpoints
  authIssuer = "https://auth.makifun.se/application/o/netbird/";
  authAuthorize = "https://auth.makifun.se/application/o/authorize/";
  authToken = "https://auth.makifun.se/application/o/token/";
  authJwks = "https://auth.makifun.se/application/o/netbird/jwks/";
  authOidc = "https://auth.makifun.se/application/o/netbird/.well-known/openid-configuration";
in
{
  systemd.tmpfiles.rules = [
    "d '${base}' 0755 root root - -"
    "d '${base}/management' 0755 root root - -"
    "d '${base}/signal' 0755 root root - -"
  ];

  sops.secrets.netbird-datastore-key = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.netbird-relay-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };
  sops.secrets.netbird-client-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # ---------------------------------------------------------------------------
  # Config generation
  # Writes management.json and relay.env from SOPS secrets.
  # Re-runs on every boot so secrets are always current.
  # To force a re-run: systemctl restart netbird-config
  # then restart the affected containers.
  # ---------------------------------------------------------------------------
  systemd.services.netbird-config = {
    description = "Generate NetBird config files from SOPS secrets";
    before = [
      "podman-netbird-dashboard.service"
      "podman-netbird-management.service"
      "podman-netbird-relay.service"
    ];
    requiredBy = [
      "podman-netbird-dashboard.service"
      "podman-netbird-management.service"
      "podman-netbird-relay.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      LoadCredential = [
        "datastore-key:${config.sops.secrets.netbird-datastore-key.path}"
        "relay-secret:${config.sops.secrets.netbird-relay-secret.path}"
        "client-secret:${config.sops.secrets.netbird-client-secret.path}"
      ];
    };
    path = [
      pkgs.coreutils
      pkgs.jq
    ];
    script = ''
      DATASTORE_KEY=$(tr -d '[:space:]' < "$CREDENTIALS_DIRECTORY/datastore-key")
      RELAY_SECRET=$(tr -d '[:space:]' < "$CREDENTIALS_DIRECTORY/relay-secret")
      CLIENT_SECRET=$(tr -d '[:space:]' < "$CREDENTIALS_DIRECTORY/client-secret")

      jq -n \
        --arg relay_secret "$RELAY_SECRET" \
        --arg datastore_key "$DATASTORE_KEY" \
        --arg client_secret "$CLIENT_SECRET" \
        '{
          TURNConfig: {
            Turns: [],
            CredentialsTTL: "12h",
            Secret: "secret",
            TimeBasedCredentials: false
          },
          Relay: {
            Addresses: ["rels://${domain}:443/relay"],
            CredentialsTTL: "24h",
            Secret: $relay_secret
          },
          Signal: { Proto: "https", URI: "${domain}:443", Username: "", Password: null },
          ReverseProxy: {
            TrustedHTTPProxies: [],
            TrustedHTTPProxiesCount: 0,
            TrustedPeers: ["0.0.0.0/0"]
          },
          DisableDefaultPolicy: false,
          Datadir: "",
          DataStoreEncryptionKey: $datastore_key,
          StoreConfig: { Engine: "sqlite" },
          HttpConfig: {
            Address: "0.0.0.0:33073",
            AuthIssuer: "${authIssuer}",
            AuthAudience: "${clientId}",
            AuthKeysLocation: "${authJwks}",
            AuthUserIDClaim: "",
            CertFile: "",
            CertKey: "",
            IdpSignKeyRefreshEnabled: false,
            OIDCConfigEndpoint: "${authOidc}"
          },
          IdpManagerConfig: {
            ManagerType: "none",
            ClientConfig: { Issuer: "", TokenEndpoint: "", ClientID: "", ClientSecret: "", GrantType: "client_credentials" },
            ExtraConfig: null,
            Auth0ClientCredentials: null,
            AzureClientCredentials: null,
            KeycloakClientCredentials: null,
            ZitadelClientCredentials: null
          },
          DeviceAuthorizationFlow: {
            Provider: "none",
            ProviderConfig: {
              Audience: "", AuthorizationEndpoint: "", Domain: "",
              ClientID: "", ClientSecret: "", TokenEndpoint: "",
              DeviceAuthEndpoint: "", Scope: "openid",
              UseIDToken: false, RedirectURLs: null
            }
          },
          PKCEAuthorizationFlow: {
            ProviderConfig: {
              Audience: "${clientId}",
              ClientID: "${clientId}",
              ClientSecret: $client_secret,
              Domain: "",
              AuthorizationEndpoint: "${authAuthorize}",
              TokenEndpoint: "${authToken}",
              Scope: "openid email profile offline_access",
              RedirectURLs: ["http://localhost:53000", "http://localhost:54000"],
              UseIDToken: false,
              DisablePromptLogin: true,
              LoginFlag: 0
            }
          }
        }' > ${base}/management.json

      # relay env file loaded by the relay container
      printf 'NB_AUTH_SECRET=%s\n' "$RELAY_SECRET" > ${base}/relay.env
      chmod 600 ${base}/relay.env

      # dashboard env file with OAuth2 client secret
      printf 'AUTH_CLIENT_SECRET=%s\n' "$CLIENT_SECRET" > ${base}/dashboard.env
      chmod 600 ${base}/dashboard.env
    '';
  };

  # ---------------------------------------------------------------------------
  # Podman network
  # ---------------------------------------------------------------------------
  systemd.services.podman-create-netbird-network = {
    description = "Create netbird_network Podman network";
    before = [
      "podman-netbird-dashboard.service"
      "podman-netbird-management.service"
      "podman-netbird-signal.service"
      "podman-netbird-relay.service"
    ];
    requiredBy = [
      "podman-netbird-dashboard.service"
      "podman-netbird-management.service"
      "podman-netbird-signal.service"
      "podman-netbird-relay.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.podman ];
    script = "podman network exists netbird_network || podman network create --subnet 10.89.3.0/24 netbird_network";
  };

  # ---------------------------------------------------------------------------
  # Containers
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = {
    netbird-dashboard = {
      image = "docker.io/netbirdio/dashboard:${dashboardTag}";
      environment = {
        NETBIRD_MGMT_API_ENDPOINT = "https://${domain}";
        NETBIRD_MGMT_GRPC_API_ENDPOINT = "https://${domain}";
        AUTH_AUDIENCE = clientId;
        AUTH_CLIENT_ID = clientId;
        AUTH_AUTHORITY = authIssuer;
        USE_AUTH0 = "false";
        AUTH_SUPPORTED_SCOPES = "openid email profile offline_access api";
        AUTH_REDIRECT_URI = "/#callback";
        AUTH_SILENT_REDIRECT_URI = "/#silent-callback";
      };
      # AUTH_CLIENT_SECRET injected at runtime from netbird-config-generated dashboard.env
      environmentFiles = [ "${base}/dashboard.env" ];
      ports = [ "127.0.0.1:8811:80" ];
      extraOptions = [ "--network=netbird_network" ];
    };

    netbird-signal = {
      image = "docker.io/netbirdio/signal:${signalTag}";
      volumes = [ "${base}/signal:/var/lib/netbird" ];
      ports = [
        "127.0.0.1:10080:80"
        "127.0.0.1:10000:10000"
      ];
      extraOptions = [ "--network=netbird_network" ];
    };

    netbird-management = {
      image = "docker.io/netbirdio/management:${managementTag}";
      volumes = [
        "${base}/management:/var/lib/netbird"
        "${base}/management.json:/etc/netbird/management.json:ro"
      ];
      cmd = [
        "--port"
        "33073"
        "--log-file"
        "console"
        "--log-level"
        "info"
        "--disable-anonymous-metrics=true"
        "--single-account-mode-domain=${domain}"
        "--dns-domain=netbird.selfhosted"
      ];
      ports = [ "127.0.0.1:33073:33073" ];
      extraOptions = [ "--network=netbird_network" ];
    };

    netbird-relay = {
      image = "docker.io/netbirdio/relay:${relayTag}";
      environment = {
        NB_LOG_LEVEL = "info";
        NB_LISTEN_ADDRESS = ":33080";
        NB_EXPOSED_ADDRESS = "rels://${domain}:443/relay";
      };
      environmentFiles = [ "${base}/relay.env" ];
      ports = [ "127.0.0.1:33080:33080" ];
      extraOptions = [ "--network=netbird_network" ];
    };
  };

  # ---------------------------------------------------------------------------
  # Traefik
  # Path-prefix routes have implicit higher priority than the catch-all dashboard.
  # Management + signal need two service definitions each: http for REST/WS,
  # h2c for gRPC (Traefik upstream HTTP/2 cleartext).
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    routers = {
      netbird-api = {
        rule = "Host(`${domain}`) && PathPrefix(`/api`)";
        entryPoints = [ "websecure" ];
        service = "netbird-api-svc";
        tls.certResolver = "letsencrypt";
      };
      netbird-mgmt-ws = {
        rule = "Host(`${domain}`) && PathPrefix(`/ws-proxy/management`)";
        entryPoints = [ "websecure" ];
        service = "netbird-api-svc";
        tls.certResolver = "letsencrypt";
      };
      netbird-mgmt-grpc = {
        rule = "Host(`${domain}`) && PathPrefix(`/management.ManagementService/`)";
        entryPoints = [ "websecure" ];
        service = "netbird-mgmt-grpc-svc";
        tls.certResolver = "letsencrypt";
      };
      netbird-signal-ws = {
        rule = "Host(`${domain}`) && PathPrefix(`/ws-proxy/signal`)";
        entryPoints = [ "websecure" ];
        service = "netbird-signal-ws-svc";
        tls.certResolver = "letsencrypt";
      };
      netbird-signal-grpc = {
        rule = "Host(`${domain}`) && PathPrefix(`/signalexchange.SignalExchange/`)";
        entryPoints = [ "websecure" ];
        service = "netbird-signal-grpc-svc";
        tls.certResolver = "letsencrypt";
      };
      netbird-relay = {
        rule = "Host(`${domain}`) && PathPrefix(`/relay`)";
        entryPoints = [ "websecure" ];
        service = "netbird-relay-svc";
        tls.certResolver = "letsencrypt";
      };
      netbird-dashboard = {
        rule = "Host(`${domain}`)";
        entryPoints = [ "websecure" ];
        service = "netbird-dashboard-svc";
        tls.certResolver = "letsencrypt";
      };
    };
    services = {
      "netbird-api-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:33073"; } ];
      "netbird-mgmt-grpc-svc".loadBalancer.servers = [ { url = "h2c://127.0.0.1:33073"; } ];
      "netbird-signal-ws-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:10080"; } ];
      "netbird-signal-grpc-svc".loadBalancer.servers = [ { url = "h2c://127.0.0.1:10000"; } ];
      "netbird-relay-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:33080"; } ];
      "netbird-dashboard-svc".loadBalancer.servers = [ { url = "http://127.0.0.1:8811"; } ];
    };
  };
}
