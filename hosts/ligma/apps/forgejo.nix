{ config, lib, pkgs, ... }:
{
  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
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
        DISABLE_REGISTRATION = false;
        ALLOW_ONLY_EXTERNAL_REGISTRATION = true;
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

      migrations = {
        ALLOWED_DOMAINS = "github.com, *.github.com, *.githubusercontent.com, *.makifun.se";
      };
    };
  };

  sops.secrets.forgejo-admin-password = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = config.services.forgejo.user;
  };

  sops.secrets.forgejo-admin-email = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = config.services.forgejo.user;
  };

  sops.secrets.forgejo-oauth-secret = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = config.services.forgejo.user;
  };

  # Wait for Authentik if it's starting, but don't hard-require it —
  # Forgejo is fully usable without Authentik (local login still works).
  systemd.services.forgejo = {
    after  = [ "authentik.service" "authentik-worker.service" ];
    wants  = [ "authentik.service" "authentik-worker.service" ];
  };

  # Append admin user creation to forgejo's existing preStart.
  # Uses || true so it's a no-op if the user already exists.
  systemd.services.forgejo.preStart = lib.mkAfter ''
    ${lib.getExe config.services.forgejo.package} admin user create \
      --admin \
      --username makifun \
      --email "$(tr -d '\n' < ${config.sops.secrets.forgejo-admin-email.path})" \
      --password "$(tr -d '\n' < ${config.sops.secrets.forgejo-admin-password.path})" \
      || true

    # Register Authentik as an OAuth2/OIDC authentication source.
    # Update the existing source if present, otherwise create it.
    # || true — failure must not block Forgejo startup (Authentik may not be ready yet).
    _auth_id=$(${lib.getExe config.services.forgejo.package} admin auth list | ${pkgs.gawk}/bin/awk '/Authentik/ {print $1}')
    if [ -n "$_auth_id" ]; then
      ${lib.getExe config.services.forgejo.package} admin auth update-oauth \
        --id "$_auth_id" \
        --key "forgejo" \
        --secret "$(tr -d '\n' < ${config.sops.secrets.forgejo-oauth-secret.path})" \
        --auto-discover-url "https://auth.makifun.se/application/o/forgejo-sso/.well-known/openid-configuration" \
        --scopes "openid email profile groups" \
        --group-claim-name "groups" \
        --admin-group "git_admins" \
        || true
    else
      ${lib.getExe config.services.forgejo.package} admin auth add-oauth \
        --name "Authentik" \
        --provider openidConnect \
        --key "forgejo" \
        --secret "$(tr -d '\n' < ${config.sops.secrets.forgejo-oauth-secret.path})" \
        --auto-discover-url "https://auth.makifun.se/application/o/forgejo-sso/.well-known/openid-configuration" \
        --scopes "openid email profile groups" \
        --group-claim-name "groups" \
        --admin-group "git_admins" \
        || true
    fi

    # Generate a short-lived API token for the provision service.
    # The CLI accesses the DB directly — no password or 2FA required.
    # /run is ephemeral so the token must be regenerated each boot; delete
    # the DB entry from any previous boot before recreating it.
    ${pkgs.sqlite}/bin/sqlite3 "${config.services.forgejo.settings.database.PATH}" \
      "DELETE FROM access_token WHERE name='forgejo-provision';" 2>/dev/null || true
    install -d -m 700 /run/forgejo
    ${lib.getExe config.services.forgejo.package} admin user generate-access-token \
      --username makifun \
      --token-name forgejo-provision \
      --scopes write:admin,read:admin,write:user,read:user \
      --raw 2>/dev/null \
      | tr -d '\n' > /run/forgejo/provision-token
    chmod 600 /run/forgejo/provision-token
    echo "forgejo-provision: token length=$(wc -c < /run/forgejo/provision-token)"
  '';

  # ---------------------------------------------------------------------------
  # Provision service accounts
  #
  # Runs after Forgejo is up on every boot. Idempotent — duplicate user/key
  # requests return 4xx which are swallowed by || true.
  # ---------------------------------------------------------------------------
  systemd.services.forgejo-provision = {
    description = "Provision Forgejo service accounts";
    after       = [ "forgejo.service" ];
    wants       = [ "forgejo.service" ];
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      User            = config.services.forgejo.user;
    };
    path   = [ pkgs.curl pkgs.openssl ];
    script = ''
      base="http://127.0.0.1:3010/api/v1"
      token="$(cat /run/forgejo/provision-token 2>/dev/null || true)"

      if [ -z "$token" ]; then
        echo "forgejo-provision: no token found in /run/forgejo/provision-token, skipping" >&2
        exit 0
      fi

      # Wait for the API to be reachable (max 60s)
      retries=0
      until curl -sf -H "Authorization: token $token" "$base/user" > /dev/null; do
        retries=$((retries + 1))
        if [ "$retries" -ge 30 ]; then
          echo "forgejo-provision: API not reachable after 60s — last response:" >&2
          curl -s -H "Authorization: token $token" "$base/user" >&2
          exit 1
        fi
        sleep 2
      done

      # Create opnsense user (409 if already exists — ignored)
      # base64 satisfies all complexity requirements: upper, lower, digit, special (+/=)
      rand_pass="$(openssl rand -base64 32)"
      http_code="$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $token" -X POST "$base/admin/users" \
        -H "Content-Type: application/json" \
        -d "{\"email\":\"opnsense@opnsense\",\"login_name\":\"opnsense\",\"username\":\"opnsense\",\"password\":\"$rand_pass\",\"restricted\":true,\"must_change_password\":false,\"send_notify\":false,\"source_id\":0}")"
      echo "forgejo-provision: create user opnsense → HTTP $http_code"

      # Add SSH key (422 if already exists — ignored)
      http_code="$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: token $token" -X POST "$base/admin/users/opnsense/keys" \
        -H "Content-Type: application/json" \
        --data-raw '{"key":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAe5wrFAm/Dw+jETfuiGWpVcy5NAGX/dM+2oFuGoKv90 opnsense_git_backup","read_only":false,"title":"opnsense_git_backup"}')"
      echo "forgejo-provision: add SSH key opnsense → HTTP $http_code"
    '';
  };

  sops.secrets.forgejo-runner-token = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "gitea-runner";
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

  # Disable DynamicUser so systemd uses /var/lib/gitea-runner directly
  # (DynamicUser redirects to /var/lib/private which conflicts with impermanence bind mounts)
  users.users.gitea-runner = {
    isSystemUser = true;
    group = "gitea-runner";
    home = "/var/lib/gitea-runner";
    extraGroups = [ "podman" ];
  };
  users.groups.gitea-runner = { };

  systemd.services."gitea-runner-default" = {
    environment.DOCKER_HOST = "unix:///run/podman/podman.sock";
    serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "gitea-runner";
      Group = "gitea-runner";
      SupplementaryGroups = [ "podman" ];
    };
  };

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/gitea-runner";
      user = "gitea-runner";
      group = "gitea-runner";
      mode = "0750";
    }
  ];

  systemd.tmpfiles.rules = [
    "d '/persist/var/lib/gitea-runner' 0750 gitea-runner gitea-runner - -"
  ];

  networking.firewall.extraInputRules = ''
    tcp dport 22222 ip saddr 10.10.10.0/24 accept comment "Forgejo SSH"
  '';

  services.traefik.dynamicConfigOptions.http = {
    routers.forgejo = {
      rule = "Host(`git.makifun.se`)";
      entryPoints = [ "websecure" ];
      service = "forgejo";
      tls.certResolver = "letsencrypt";
    };
    services.forgejo.loadBalancer.servers = [ { url = "http://127.0.0.1:3010"; } ];
  };
}
