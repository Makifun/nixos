{
  baseFacts,
  config,
  pkgs,
  ...
}:
let
  hostname = config.networking.hostName;
  jellyfinBase = "/${hostname}/${hostname}/jellyfin";
  jellyfinUrl = "https://jellyfin.${baseFacts.domainName}";
  # renovate: datasource=docker depName=lscr.io/linuxserver/jellyfin
  jellyfinTag = "12.1ubu2604-ls50";

  # Provider config for the Flowfin/jellyfin-plugin-sso plugin, read at startup.
  # Setup notes: Obsidian vault, [[jellyfin]].
  ssoProviders = pkgs.writeText "jellyfin-sso-providers.json" (
    builtins.toJSON {
      FormatVersion = 1;
      Configuration = {
        OidConfigs.Authentik = {
          Enabled = true;
          OidEndpoint = "https://auth.${baseFacts.domainName}/application/o/jellyfin/.well-known/openid-configuration";
          OidClientId = "jellyfin";
          OidSecretFile = "/run/secrets/jellyfin-oidc-secret";
          AllowPrivateNetworkAddresses = true;
          BaseUrlOverride = jellyfinUrl;
          OidScopes = [
            "email"
            "groups"
          ];
          RoleClaim = "groups";
          DefaultUsernameClaim = "preferred_username";
          EnableAuthorization = false;
        };
        SamlConfigs = { };
      };
    }
  );
in
{
  sops.secrets.jellyfin-oidc-secret = {
    sopsFile = ../secrets.yaml;
    uid = 1000;
    gid = 1000;
    mode = "0400";
    restartUnits = [ "podman-jellyfin.service" ];
  };

  systemd.tmpfiles.rules = [
    "d '${jellyfinBase}/config' 0750 1000 1000 - -"
    "d '/transcode/jellyfin'    0775 1000 1000 - -"
  ];

  # Start after rclone mounts /cloud so media is available on startup.
  systemd.services.podman-jellyfin = {
    after = [ "rclone-cloud.service" ];
    bindsTo = [ "rclone-cloud.service" ];
  };

  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:${jellyfinTag}";
    extraOptions = [
      "--network=host"
      "--device=/dev/dri:/dev/dri"
      "--no-healthcheck"
    ];
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = config.time.timeZone;
      JELLYFIN_PublishedServerUrl = jellyfinUrl;
      JELLYFIN_SSO_CONFIG_FILE = "/run/sso/providers.json";
    };
    volumes = [
      "${jellyfinBase}/config:/config"
      "/transcode/jellyfin:/config/cache"
      "/cloud:/cloud:ro"
      "${ssoProviders}:/run/sso/providers.json:ro"
      "${config.sops.secrets.jellyfin-oidc-secret.path}:/run/secrets/jellyfin-oidc-secret:ro"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    8096 # Jellyfin web UI + API
  ];
  networking.firewall.allowedUDPPorts = [
    7359 # Jellyfin client discovery
  ];
}
