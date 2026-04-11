{ config, ... }:
{
  services.vaultwarden = {
    enable = true;
    # Secret file must contain:
    #   ADMIN_TOKEN=<argon2 hash or plaintext token>
    environmentFile = config.sops.secrets.vaultwarden_env.path;
    config = {
      DATA_FOLDER = "/ligma/ligma/vaultwarden";
      DOMAIN = "https://vault.makifun.se";
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8310;
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;
      LOG_LEVEL = "warn";
      EXTENDED_LOGGING = true;
      # SSO via Authentik OIDC — client secret comes from vaultwarden_env
      SSO_ENABLED = true;
      SSO_CLIENT_ID = "vaultwarden";
      SSO_AUTHORITY = "https://auth.makifun.se/application/o/vaultwarden-sso/";
      SSO_SCOPES = "email profile offline_access";
      SSO_SIGNUPS_MATCH_EMAIL = true;
      SSO_CLIENT_CACHE_EXPIRATION = 0;
    };
  };

  systemd.services.vaultwarden.serviceConfig.ReadWritePaths = [ "/ligma/ligma/vaultwarden" ];

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/vaultwarden' 0700 vaultwarden vaultwarden - -"
  ];

  sops.secrets.vaultwarden_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "vaultwarden";
  };

  environment.etc."fail2ban/filter.d/vaultwarden.conf".text = ''
    [INCLUDES]
    before = common.conf

    [Definition]
    failregex = ^.*Username or password is incorrect\. Try again\. IP: <HOST>\..*$
                ^.*Invalid admin token\. IP: <HOST>\..*$

    ignoreregex =

    journalmatch = _SYSTEMD_UNIT=vaultwarden.service
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
      rule = "Host(`vault.makifun.se`)";
      entryPoints = [ "websecure" ];
      service = "vaultwarden";
      tls.certResolver = "letsencrypt";
    };
    services.vaultwarden.loadBalancer.servers = [ { url = "http://127.0.0.1:8310"; } ];
  };
}
