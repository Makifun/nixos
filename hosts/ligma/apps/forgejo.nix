{ config, ... }:
{
  services.forgejo = {
    enable = true;

    # Environment file with secrets in FORGEJO__section__KEY=value format.
    # Required keys: FORGEJO__security__SECRET_KEY, FORGEJO__security__INTERNAL_TOKEN
    # Generate with: nix run nixpkgs#forgejo -- generate secret SECRET_KEY
    #                nix run nixpkgs#forgejo -- generate secret INTERNAL_TOKEN
    secretFile = config.sops.secrets.forgejo_env.path;

    settings = {
      DEFAULT.APP_NAME = "Forgejo";

      server = {
        DOMAIN = "ligma";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3000;
        ROOT_URL = "http://ligma";
        # Forgejo's built-in SSH server for git operations
        SSH_DOMAIN = "ligma";
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
        COOKIE_SECURE = false; # set to true once behind HTTPS
        SESSION_LIFE_TIME = 86400;
      };

      log = {
        MODE = "console";
        LEVEL = "warn";
      };

      other = {
        SHOW_FOOTER_VERSION = false;
        SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
      };
    };
  };

  # Persist Forgejo state across reboots
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/forgejo";
      user = "forgejo";
      group = "forgejo";
      mode = "0750";
    }
  ];

  # Nginx reverse proxy on port 80
  services.nginx = {
    enable = true;
    virtualHosts."ligma" = {
      default = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        extraConfig = ''
          client_max_body_size 100M;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };

  # Allow Forgejo's git SSH from the local subnet
  networking.firewall.extraInputRules = ''
    tcp dport 22222 accept comment "Forgejo SSH"
  '';

  sops.secrets.forgejo_env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "forgejo";
  };
}
