{
  baseFacts,
  config,
  hosts,
  ...
}:
let
  hostname = config.networking.hostName;
  vaultwardenPort = 8310;
  vaultwardenBase = "/${hostname}/${hostname}/vaultwarden";
  # renovate: datasource=docker depName=vaultwarden/server
  vaultwardenTag = "1.37.1";
in
{
  # vaultwarden_env: |
  #   ADMIN_TOKEN=<token>
  #   SSO_CLIENT_SECRET=<secret>
  sops.secrets.vaultwarden_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "root";
  };

  # Data dir owned by UID/GID 1000 — vaultwarden container runs as that user.
  systemd.tmpfiles.rules = [
    "d '${vaultwardenBase}' 0700 1000 1000 - -"
  ];

  virtualisation.oci-containers.containers.vaultwarden = {
    image = "docker.io/vaultwarden/server:${vaultwardenTag}";
    ports = [ "127.0.0.1:${toString vaultwardenPort}:80" ];
    environment = {
      DATA_FOLDER = "/data";
      DOMAIN = "https://vault.${baseFacts.domainName}";
      SIGNUPS_ALLOWED = "false";
      INVITATIONS_ALLOWED = "false";
      SHOW_PASSWORD_HINT = "false";
      LOG_LEVEL = "warn";
      EXTENDED_LOGGING = "true";
      SSO_ENABLED = "true";
      SSO_CLIENT_ID = "vaultwarden";
      SSO_AUTHORITY = "https://auth.${baseFacts.domainName}/application/o/vaultwarden-sso/";
      SSO_SCOPES = "email profile offline_access";
      SSO_SIGNUPS_MATCH_EMAIL = "true";
      SSO_CLIENT_CACHE_EXPIRATION = "0";
    };
    environmentFiles = [ config.sops.secrets.vaultwarden_env.path ];
    volumes = [ "${vaultwardenBase}:/data" ];
  };

  environment.etc."fail2ban/filter.d/vaultwarden.conf".text = ''
    [INCLUDES]
    before = common.conf

    [Definition]
    failregex = ^.*Username or password is incorrect\. Try again\. IP: <HOST>\..*$
                ^.*Invalid admin token\. IP: <HOST>\..*$

    ignoreregex =

    journalmatch = _SYSTEMD_UNIT=podman-vaultwarden.service
  '';

  services.fail2ban.jails.vaultwarden = {
    settings = {
      enabled = true;
      filter = "vaultwarden";
      backend = "systemd";
      port = "80,443";
      maxretry = 5;
      findtime = 14400;
      bantime = 14400;
    };
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.vaultwarden = {
      rule = "Host(`vault.${baseFacts.domainName}`)";
      entryPoints = [ "websecure" ];
      service = "vaultwarden";
      tls.certResolver = "letsencrypt";
    };
    services.vaultwarden.loadBalancer.servers = [
      { url = "http://127.0.0.1:${toString vaultwardenPort}"; }
    ];
  };

  ligma.dnsRecords."vault.${baseFacts.domainName}".value = hosts.ligma;
}
