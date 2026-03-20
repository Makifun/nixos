{ ... }:
{
  services.forgejo = {
    enable = true;
    # /ligma is a persistent ZFS dataset (zstorage pool) — no impermanence needed.
    # SECRET_KEY, INTERNAL_TOKEN, and JWT secrets are auto-generated on first boot.
    stateDir = "/ligma/ligma/forgejo";

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
        LEVEL = "Warn";
      };

      other = {
        SHOW_FOOTER_VERSION = false;
        SHOW_FOOTER_TEMPLATE_LOAD_TIME = false;
      };
    };
  };

  # Ensure parent directory exists on the ZFS pool before forgejo's tmpfiles run
  systemd.tmpfiles.rules = [
    "d '/ligma/ligma' 0755 root root - -"
  ];

  # Traefik (via Pangolin) handles reverse proxying — see pangolin.nix

  # Allow Forgejo's git SSH from the local subnet
  networking.firewall.extraInputRules = ''
    tcp dport 22222 ip saddr 10.10.10.0/24 accept comment "Forgejo SSH"
  '';
}
