{ config, lib, pkgs, ... }:
{
  services.forgejo = {
    enable = true;
    stateDir = "/ligma/ligma/forgejo";
    lfs.enable = true;

    settings = {
      DEFAULT.APP_NAME = "Forgejo";

      server = {
        DOMAIN = "git.makifun.se";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3010;
        ROOT_URL = "https://git.makifun.se/";
        SSH_DOMAIN = "git.makifun.se";
        SSH_PORT = 22222;
        SSH_LISTEN_PORT = 22222;
        START_SSH_SERVER = true;
        DISABLE_SSH = false;
      };

      database.DB_TYPE = "sqlite3";

      repository = {
        DEFAULT_PRIVATE = "private";
        DEFAULT_PUSH_CREATE_PRIVATE = true;
        ENABLE_PUSH_CREATE_USER = true;
      };

      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
        DEFAULT_ALLOW_CREATE_ORGANIZATION = false;
        DEFAULT_USER_VISIBILITY = "private";
        DEFAULT_ORG_VISIBILITY = "private";
      };

      security = {
        MIN_PASSWORD_LENGTH = 12;
        PASSWORD_COMPLEXITY = "lower,upper,digit,spec";
        LOGIN_REMEMBER_DAYS = 7;
        DISABLE_GIT_HOOKS = false;
      };

      session = {
        COOKIE_SECURE = true;
        SESSION_LIFE_TIME = 86400;
      };

      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "github";
      };

      log = {
        MODE = "console";
        LEVEL = "Warn";
      };

      other = {
        SHOW_FOOTER_VERSION = false;
        SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
      };
    };
  };

  sops.secrets.forgejo-admin-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = config.services.forgejo.user;
  };

  # Append admin user creation to forgejo's existing preStart.
  # Uses || true so it's a no-op if the user already exists.
  systemd.services.forgejo.preStart = lib.mkAfter ''
    ${lib.getExe config.services.forgejo.package} admin user create \
      --admin \
      --username makifun \
      --email "admin@makifun.se" \
      --password "$(tr -d '\n' < ${config.sops.secrets.forgejo-admin-password.path})" \
      || true
  '';

  sops.secrets.forgejo-runner-token = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.default = {
      enable = true;
      name = "monolith";
      url = "https://git.makifun.se";
      tokenFile = config.sops.secrets.forgejo-runner-token.path;
      labels = [
        "ubuntu-latest:docker://node:16-bullseye"
      ];
    };
  };

  environment.persistence."/persist".directories = [
    "/var/lib/gitea-runner"
  ];

  # Podman docker-compat socket access for the runner
  systemd.services."gitea-runner-default".serviceConfig.SupplementaryGroups = [ "podman" ];

  networking.firewall.extraInputRules = ''
    tcp dport 22222 ip saddr 10.10.10.0/24 accept comment "Forgejo SSH"
  '';
}
