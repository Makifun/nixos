{ config, ... }:
let
  zotPort = 5000;
  zotBase = "/var/lib/zot";
in
{
  # ---------------------------------------------------------------------------
  # Zot OCI registry
  #
  # Pull-through cache + own image storage.
  # Does NOT use Authentik — docker clients speak Bearer auth directly to Zot.
  #
  # Bootstrap:
  #   1. Generate htpasswd entry (bcrypt):
  #        nix-shell -p apacheHttpd --run 'htpasswd -nB makifun'
  #   2. Add to secrets.yaml:
  #        zot-htpasswd: "makifun:$2y$05$..."
  #   3. Deploy → docker login registry.makifun.se
  #
  # Pulling through the cache:
  #   docker pull registry.makifun.se/dockerhub/library/nginx:latest
  #   docker pull registry.makifun.se/dockerhub/linuxserver/sonarr:latest
  #   docker pull registry.makifun.se/ghcr/owner/image:tag
  #   docker pull registry.makifun.se/quay/owner/image:tag
  #
  # Pushing own images:
  #   docker tag myimage registry.makifun.se/myimage:tag
  #   docker push registry.makifun.se/myimage:tag
  # ---------------------------------------------------------------------------

  sops.secrets.zot-htpasswd = {
    format   = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Static config — no secrets inline; htpasswd is mounted from SOPS path.
  environment.etc."zot/config.json".text = builtins.toJSON {
    distSpecVersion = "1.1.0";
    storage = {
      rootDirectory = "/var/lib/zot";
      gc            = true;
      gcDelay       = "1h";
      gcInterval    = "24h";
    };
    http = {
      address = "0.0.0.0";
      port    = toString zotPort;
      auth.htpasswd.path = "/etc/zot/htpasswd";
    };
    log.level = "info";
    extensions = {
      search.enable = true;  # GraphQL API powering the UI
      ui.enable     = true;  # Web UI at https://registry.makifun.se
      sync = {
      enable     = true;
      registries = [
        # Docker Hub — official images: .../dockerhub/library/nginx
        #             user images:      .../dockerhub/username/image
        {
          urls      = [ "https://registry-1.docker.io" ];
          onDemand  = true;
          tlsVerify = true;
          content   = [{ prefix = "**"; destination = "/dockerhub"; }];
        }
        # GitHub Container Registry — .../ghcr/owner/image
        {
          urls      = [ "https://ghcr.io" ];
          onDemand  = true;
          tlsVerify = true;
          content   = [{ prefix = "**"; destination = "/ghcr"; }];
        }
        # Quay.io — .../quay/owner/image
        {
          urls      = [ "https://quay.io" ];
          onDemand  = true;
          tlsVerify = true;
          content   = [{ prefix = "**"; destination = "/quay"; }];
        }
        # LinuxServer (lscr.io) — .../lscr/linuxserver/sonarr
        {
          urls      = [ "https://lscr.io" ];
          onDemand  = true;
          tlsVerify = true;
          content   = [{ prefix = "**"; destination = "/lscr"; }];
        }
      ];
    };      # sync
  };        # extensions
  };

  virtualisation.oci-containers.containers.zot = {
    image = "ghcr.io/project-zot/zot-linux-amd64:latest";
    ports = [ "127.0.0.1:${toString zotPort}:${toString zotPort}" ];
    volumes = [
      "/etc/zot/config.json:/etc/zot/config.json:ro"
      "${config.sops.secrets.zot-htpasswd.path}:/etc/zot/htpasswd:ro"
      "${zotBase}:/var/lib/zot:z"
    ];
  };

  environment.persistence."/persist".directories = [
    {
      directory = "${zotBase}";
      user = "root";
      group = "root";
      mode = "0750";
    }
  ];

  services.traefik.dynamicConfigOptions.http = {
    routers.zot = {
      rule             = "Host(`registry.makifun.se`)";
      entryPoints      = [ "websecure" ];
      service          = "zot";
      tls.certResolver = "letsencrypt";
      # No Authentik middleware — docker clients use Zot's own Bearer auth
    };
    services.zot.loadBalancer.servers = [{ url = "http://127.0.0.1:${toString zotPort}"; }];
  };
}
