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
      INVITATIONS_ALLOWED = true;
      SHOW_PASSWORD_HINT = false;
    };
  };

  systemd.tmpfiles.rules = [
    "d '/ligma/ligma/vaultwarden' 0700 vaultwarden vaultwarden - -"
  ];

  sops.secrets.vaultwarden_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "vaultwarden";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers.vaultwarden = {
      rule = "Host(`vaultwarden.makifun.se`)";
      entryPoints = [ "websecure" ];
      service = "vaultwarden";
      tls.certResolver = "letsencrypt";
    };
    services.vaultwarden.loadBalancer.servers = [ { url = "http://127.0.0.1:8310"; } ];
  };
}
