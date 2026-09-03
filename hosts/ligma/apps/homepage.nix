{
  baseFacts,
  config,
  hosts,
  ...
}:
{
  sops.secrets.homepage-env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  sops.secrets.homepage-kubeconfig = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "homepage-dashboard";
  };

  systemd.services.homepage-dashboard.environment = {
    KUBECONFIG = config.sops.secrets.homepage-kubeconfig.path;
    # Raise libuv thread pool from default 4 → 32.
    UV_THREADPOOL_SIZE = "32";
  };

  environment.etc."homepage-dashboard/images".source = ../homepage_images;

  users.users.homepage-dashboard = {
    isSystemUser = true;
    group = "homepage-dashboard";
    extraGroups = [ "podman" ];
  };
  users.groups.homepage-dashboard = { };

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "localhost:8082,127.0.0.1:8082,homepage.${baseFacts.domainName}";
    environmentFiles = [ config.sops.secrets.homepage-env.path ];

    kubernetes = {
      mode = "default";
      gateway = true;
    };

    docker = {
      bofa = {
        host = hosts.bofa;
        port = 2375;
      };
      ligma = {
        socket = "/run/podman/podman.sock";
      };
      playma = {
        host = hosts.playma;
        port = 2375;
      };
    };

    settings = {
      layout = [
        {
          Media = {
            style = "column";
          };
        }
        {
          Downloads = {
            style = "column";
          };
        }
        {
          DVR = {
            style = "column";
          };
        }
        {
          DVR4K = {
            style = "column";
          };
        }
        {
          Calendar = {
            style = "column";
          };
        }
        {
          Utilities = {
            style = "column";
            columns = 1;
          };
        }
        {
          Network = {
            style = "column";
            columns = 1;
          };
        }
        {
          Server = {
            style = "column";
            columns = 1;
          };
        }
      ];
      headerStyle = "boxed";
      color = "slate";
      theme = "dark";
      hideVersion = true;
      background = "/images/background.png";
      backgroundOpacity = 0.9;
      disableCollapse = true;
    };

    widgets = [
      {
        resources = {
          label = "System";
          cpu = true;
          memory = true;
          uptime = true;
          expanded = true;
        };
      }
      {
        resources = {
          label = "/";
          disk = "/";
          expanded = true;
        };
      }
      {
        resources = {
          label = "/persist";
          disk = "/persist";
          expanded = true;
        };
      }
      {
        resources = {
          label = "/ligma";
          disk = "/ligma";
          expanded = true;
        };
      }
      {
        unifi_console = {
          url = "https://unifi.${baseFacts.domainName}";
          username = "{{HOMEPAGE_VAR_UNIFI_USERNAME}}";
          password = "{{HOMEPAGE_VAR_UNIFI_PASSWORD}}";
        };
      }
      {
        openmeteo = {
          label = "{{HOMEPAGE_VAR_OPENMETEO_LABEL}}";
          latitude = "{{HOMEPAGE_VAR_OPENMETEO_LATITUDE}}";
          longitude = "{{HOMEPAGE_VAR_OPENMETEO_LONGITUDE}}";
          units = "metric";
          cache = 5;
        };
      }
      {
        datetime = {
          locale = "sv";
          format = {
            dateStyle = "long";
            timeStyle = "short";
          };
        };
      }
    ];

    services = [
      {
        "Media" = [
          {
            "Plex" = {
              icon = "/images/plex.png";
              href = "https://app.plex.tv";
              server = "playma";
              container = "plex";
              widget = {
                type = "plex";
                fields = [
                  "streams"
                  "movies"
                  "tv"
                ];
                url = "https://${hosts.playma}:32400";
                key = "{{HOMEPAGE_VAR_PLEX_TOKEN}}";
              };
            };
          }
          {
            "Tracearr" = {
              icon = "/images/tracearr.png";
              href = "https://tracearr.${baseFacts.domainName}";
              namespace = "tracearr";
              app = "tracearr";
              widget = {
                type = "tracearr";
                url = "https://tracearr.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_TRACEARR_TOKEN}}";
                view = "both";
                enableUser = true;
                showEpisodeNumber = true;
                expandOneStreamToTwoRows = false;
              };
            };
          }
          {
            "Seerr" = {
              icon = "/images/seerr.png";
              href = "https://seerr.${baseFacts.domainName}";
              namespace = "seerr";
              app = "seerr";
              widget = {
                type = "seerr";
                fields = [
                  "pending"
                  "approved"
                  "available"
                  "processing"
                ];
                url = "https://seerr.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_SEERR_TOKEN}}";
              };
            };
          }
        ];
      }

      {
        "Downloads" = [
          {
            "NZBget" = {
              icon = "/images/nzbget.png";
              href = "https://nzbget.${baseFacts.domainName}";
              namespace = "nzbget";
              app = "nzbget";
              widget = {
                type = "nzbget";
                url = "https://nzbget.${baseFacts.domainName}";
                username = "{{HOMEPAGE_VAR_NZBGET_USERNAME}}";
                password = "{{HOMEPAGE_VAR_NZBGET_PASSWORD}}";
              };
            };
          }
          {
            "qBittorrent" = {
              icon = "/images/qbittorrent.png";
              href = "https://qui.${baseFacts.domainName}/instances/1";
              namespace = "media";
              app = "media";
              widget = {
                type = "qbittorrent";
                fields = [
                  "leech"
                  "download"
                  "seed"
                  "upload"
                ];
                url = "https://qbittorrent.${baseFacts.domainName}";
                enableLeechProgress = true;
              };
            };
          }
          {
            "Autobrr" = {
              icon = "/images/autobrr.png";
              href = "https://autobrr.${baseFacts.domainName}";
              namespace = "media";
              app = "media";
              widget = {
                type = "autobrr";
                fields = [
                  "approvedPushes"
                  "rejectedPushes"
                  "filters"
                  "indexers"
                ];
                url = "https://autobrr.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_AUTOBRR_TOKEN}}";
              };
            };
          }
          {
            "Prowlarr" = {
              icon = "/images/prowlarr.png";
              href = "https://prowlarr.${baseFacts.domainName}";
              namespace = "media";
              app = "media";
              widget = {
                type = "prowlarr";
                url = "https://prowlarr.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_PROWLARR_TOKEN}}";
              };
            };
          }
        ];
      }

      {
        "DVR" = [
          {
            "Sonarr" = {
              icon = "/images/sonarr.png";
              href = "https://sonarr.${baseFacts.domainName}";
              namespace = "sonarr";
              app = "sonarr";
              widget = {
                type = "sonarr";
                fields = [
                  "wanted"
                  "queued"
                  "series"
                ];
                url = "https://sonarr.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_SONARR_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Radarr" = {
              icon = "/images/radarr.png";
              href = "https://radarr.${baseFacts.domainName}";
              namespace = "radarr";
              app = "radarr";
              widget = {
                type = "radarr";
                fields = [
                  "wanted"
                  "missing"
                  "queued"
                  "movies"
                ];
                url = "https://radarr.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_RADARR_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Bazarr" = {
              icon = "/images/bazarr.png";
              href = "https://bazarr.${baseFacts.domainName}";
              namespace = "bazarr";
              app = "bazarr";
              widget = {
                type = "bazarr";
                url = "https://bazarr.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_BAZARR_TOKEN}}";
              };
            };
          }
        ];
      }

      {
        "DVR4K" = [
          {
            "Sonarr4K" = {
              icon = "/images/sonarr4k.png";
              href = "https://sonarr4k.${baseFacts.domainName}";
              namespace = "sonarr4k";
              app = "sonarr4k";
              widget = {
                type = "sonarr";
                fields = [
                  "wanted"
                  "queued"
                  "series"
                ];
                url = "https://sonarr4k.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_SONARR4K_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Radarr4K" = {
              icon = "/images/radarr4k.png";
              href = "https://radarr4k.${baseFacts.domainName}";
              namespace = "radarr4k";
              app = "radarr4k";
              widget = {
                type = "radarr";
                fields = [
                  "wanted"
                  "missing"
                  "queued"
                  "movies"
                ];
                url = "https://radarr4k.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_RADARR4K_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Bazarr4K" = {
              icon = "/images/bazarr4k.png";
              href = "https://bazarr4k.${baseFacts.domainName}";
              namespace = "bazarr4k";
              app = "bazarr4k";
              widget = {
                type = "bazarr";
                url = "https://bazarr4k.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_BAZARR4K_TOKEN}}";
              };
            };
          }
        ];
      }

      {
        "Calendar" = [
          {
            "Calendar" = {
              widget = {
                type = "calendar";
                maxEvents = 100;
                showTime = true;
                integrations = [
                  {
                    type = "sonarr";
                    service_group = "DVR";
                    service_name = "Sonarr";
                  }
                  {
                    type = "radarr";
                    service_group = "DVR";
                    service_name = "Radarr";
                  }
                ];
              };
            };
          }
        ];
      }

      {
        "Utilities" = [
          {
            "Miniflux" = {
              icon = "/images/miniflux.svg";
              href = "https://miniflux.${baseFacts.domainName}";
              namespace = "miniflux";
              app = "miniflux";
              widget = {
                type = "miniflux";
                url = "https://miniflux.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_MINIFLUX_TOKEN}}";
              };
            };
          }
          {
            "Home Assistant" = {
              icon = "/images/home-assistant.png";
              href = "https://homeassistant.${baseFacts.domainName}";
              namespace = "homeassistant";
              app = "homeassistant";
              widget = {
                type = "homeassistant";
                url = "https://homeassistant.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_HOMEASSISTANT_TOKEN}}";
              };
            };
          }
          {
            "HAVC" = {
              icon = "/images/havc.png";
              href = "https://havc.${baseFacts.domainName}";
              namespace = "homeassistant";
              app = "homeassistant";
            };
          }
          {
            "Forgejo" = {
              icon = "/images/forgejo.png";
              href = "https://git.${baseFacts.domainName}/pulls?type=your_repositories";
              widget = {
                type = "gitea";
                fields = [
                  "repositories"
                  "issues"
                  "pulls"
                ];
                url = "https://git.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_FORGEJO_TOKEN}}";
              };
            };
          }
          {
            "makifun/nixos" = {
              icon = "si-github";
              href = "https://github.com/Makifun/nixos/pulls";
              widget = {
                type = "customapi";
                url = "https://api.github.com/search/issues?q=repo:Makifun/nixos+is:pr+state:open";
                refreshInterval = 3600000;
                method = "GET";
                headers = {
                  "User-Agent" = "homepage-dashboard";
                };
                mappings = [
                  {
                    field = "total_count";
                    label = "Pull Requests";
                    format = "number";
                  }
                ];
              };
            };
          }
          {
            "Vaultwarden" = {
              icon = "/images/vaultwarden.png";
              href = "https://vault.${baseFacts.domainName}";
              server = "ligma";
              container = "vaultwarden";
            };
          }
          {
            "Filebrowser" = {
              icon = "/images/filebrowser.png";
              href = "https://filebrowser.${baseFacts.domainName}";
              namespace = "filebrowser";
              app = "filebrowser";
            };
          }
          {
            "s3manager-garage" = {
              icon = "/images/s3man.png";
              href = "https://s3manager-garage.${baseFacts.domainName}";
              namespace = "s3manager";
              app = "s3manager-garage";
            };
          }
          {
            "s3manager-offsite" = {
              icon = "/images/s3man.png";
              href = "https://s3manager-offsite.${baseFacts.domainName}";
              namespace = "s3manager";
              app = "s3manager-offsite";
            };
          }
          {
            "Garage S3" = {
              icon = "/images/garages3.svg";
              server = "ligma";
              container = "garage";
            };
          }
          {
            "TimescaleDB" = {
              icon = "/images/timescaledb.png";
              server = "bofa";
              container = "timescaledb";
            };
          }
          {
            "pgAdmin" = {
              icon = "/images/pgadmin.png";
              href = "https://pgadmin.${baseFacts.domainName}";
              server = "ligma";
              container = "pgadmin";
            };
          }
          {
            "pgBackWeb" = {
              icon = "/images/pgbackweb.png";
              href = "https://pgbackweb.${baseFacts.domainName}";
              namespace = "postgres";
              app = "pgbackweb";
            };
          }
          {
            "Profilarr" = {
              icon = "/images/profilarr.png";
              href = "https://profilarr.${baseFacts.domainName}";
              namespace = "profilarr";
              app = "profilarr";
            };
          }
          {
            "Gotify" = {
              icon = "/images/gotify.png";
              href = "https://gotify.${baseFacts.domainName}";
              server = "ligma";
              container = "gotify";
            };
          }
          {
            "Apprise" = {
              icon = "/images/apprise.png";
              href = "https://apprise.${baseFacts.domainName}";
              server = "ligma";
              container = "apprise";
            };
          }
          {
            "MediaInfo" = {
              icon = "/images/mediainfo.png";
              href = "https://mediainfo.${baseFacts.domainName}";
              namespace = "mediainfo";
              app = "mediainfo";
            };
          }
          {
            "PrivateBin" = {
              icon = "/images/privatebin.png";
              href = "https://privatebin.${baseFacts.domainName}";
              namespace = "privatebin";
              app = "privatebin";
            };
          }
          {
            "KasmCord" = {
              icon = "/images/discord.png";
              href = "https://kasmcord.${baseFacts.domainName}";
              namespace = "kasmcord";
              app = "kasmcord";
            };
          }
          {
            "Rclone Playma" = {
              icon = "/images/rclone.png";
              href = "https://rclone-playma.${baseFacts.domainName}";
            };
          }
        ];
      }

      {
        "Network" = [
          {
            "OPNsense" = {
              icon = "/images/opnsense.png";
              href = "https://opnsense.${baseFacts.domainName}";
              widget = {
                type = "opnsense";
                url = "https://opnsense.${baseFacts.domainName}";
                username = "{{HOMEPAGE_VAR_OPNSENSE_USERNAME}}";
                password = "{{HOMEPAGE_VAR_OPNSENSE_PASSWORD}}";
              };
            };
          }
          {
            "Technitium" = {
              icon = "/images/technitium.png";
              href = "https://technitium.${baseFacts.domainName}";
              widget = {
                type = "technitium";
                fields = [
                  "totalQueries"
                  "totalAuthoritative"
                  "totalCached"
                  "totalBlocked"
                ];
                url = "https://technitium.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_TECHNITIUM_TOKEN}}";
              };
            };
          }
          {
            "Unifi Controller" = {
              icon = "/images/unifi.png";
              href = "https://unifi.${baseFacts.domainName}";
              server = "ligma";
              container = "unifi";
              widget = {
                type = "unifi";
                url = "https://unifi.${baseFacts.domainName}";
                username = "{{HOMEPAGE_VAR_UNIFI_USERNAME}}";
                password = "{{HOMEPAGE_VAR_UNIFI_PASSWORD}}";
              };
            };
          }
          {
            "WatchYourLAN" = {
              icon = "/images/watchyourlan.png";
              server = "ligma";
              container = "watchyourlan";
              href = "https://watchyourlan.${baseFacts.domainName}";
              widget = {
                type = "customapi";
                url = "https://watchyourlan.${baseFacts.domainName}/api/status/";
                refreshInterval = 300000;
                method = "GET";
                display = "block";
                mappings = [
                  {
                    field = "Online";
                    label = "Online";
                    format = "number";
                  }
                  {
                    field = "Offline";
                    label = "Offline";
                    format = "number";
                  }
                  {
                    field = "Known";
                    label = "Known";
                    format = "number";
                  }
                  {
                    field = "Unknown";
                    label = "Unknown";
                    format = "number";
                  }
                ];
              };
            };
          }
        ];
      }

      {
        "Server" = [
          {
            "Proxmox" = {
              icon = "/images/proxmox.png";
              href = "https://proxmoxifun.${baseFacts.domainName}:8006";
              widget = {
                type = "proxmox";
                fields = [
                  "vms"
                  "resources.cpu"
                  "resources.mem"
                ];
                url = "https://proxmoxifun.${baseFacts.domainName}:8006";
                username = "{{HOMEPAGE_VAR_PROXMOX_USERNAME}}";
                password = "{{HOMEPAGE_VAR_PROXMOX_PASSWORD}}";
              };
            };
          }
          {
            "Omni" = {
              icon = "/images/sidero.png";
              href = "https://omni.${baseFacts.domainName}";
              server = "ligma";
              container = "omni";
            };
          }
          {
            "Grafana" = {
              icon = "/images/grafana.png";
              href = "https://grafana.${baseFacts.domainName}";
            };
          }
          {
            "Prometheus" = {
              icon = "/images/prometheus.png";
              href = "https://prometheus.${baseFacts.domainName}";
              widget = {
                type = "prometheus";
                url = "http://localhost:9090";
              };
            };
          }
          {
            "Backrest Bofa" = {
              icon = "/images/backrest.png";
              href = "https://backrest-bofa.${baseFacts.domainName}";
              server = "bofa";
              container = "backrest";
              widget = {
                type = "backrest";
                url = "https://backrest-bofa.${baseFacts.domainName}";
              };
            };
          }
          {
            "Backrest Ligma" = {
              icon = "/images/backrest.png";
              href = "https://backrest-ligma.${baseFacts.domainName}";
              server = "ligma";
              container = "backrest";
              widget = {
                type = "backrest";
                url = "http://127.0.0.1:9898";
              };
            };
          }
          {
            "Backrest Playma" = {
              icon = "/images/backrest.png";
              href = "https://backrest-playma.${baseFacts.domainName}";
              server = "playma";
              container = "backrest";
              widget = {
                type = "backrest";
                url = "https://backrest-playma.${baseFacts.domainName}";
              };
            };
          }
          {
            "Backrest Sugma" = {
              icon = "/images/backrest.png";
              href = "https://backrest-sugma.${baseFacts.domainName}";
              namespace = "backrest";
              app = "backrest";
              widget = {
                type = "backrest";
                url = "https://backrest-sugma.${baseFacts.domainName}";
              };
            };
          }
          {
            "Beszel Bofa" = {
              icon = "/images/beszel.svg";
              href = "https://beszel.${baseFacts.domainName}";
              server = "bofa";
              container = "beszel-agent";
              widget = {
                type = "beszel";
                fields = [
                  "cpu"
                  "memory"
                  "disk"
                  "network"
                ];
                url = "https://beszel.${baseFacts.domainName}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_BOFA}}";
                version = 2;
              };
            };
          }
          {
            "Beszel Ligma" = {
              icon = "/images/beszel.svg";
              href = "https://beszel.${baseFacts.domainName}";
              server = "ligma";
              container = "beszel";
              widget = {
                type = "beszel";
                fields = [
                  "cpu"
                  "memory"
                  "disk"
                  "network"
                ];
                url = "https://beszel.${baseFacts.domainName}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_LIGMA}}";
                version = 2;
              };
            };
          }
          {
            "Beszel Playma" = {
              icon = "/images/beszel.svg";
              href = "https://beszel.${baseFacts.domainName}";
              server = "playma";
              container = "beszel-agent";
              widget = {
                type = "beszel";
                fields = [
                  "cpu"
                  "memory"
                  "disk"
                  "network"
                ];
                url = "https://beszel.${baseFacts.domainName}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_PLAYMA}}";
                version = 2;
              };
            };
          }
          {
            "Beszel Sugma01" = {
              icon = "/images/beszel.svg";
              href = "https://beszel.${baseFacts.domainName}";
              namespace = "monitoring";
              app = "beszel-agent-sugma01";
              widget = {
                type = "beszel";
                fields = [
                  "cpu"
                  "memory"
                  "disk"
                  "network"
                ];
                url = "https://beszel.${baseFacts.domainName}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_SUGMA01}}";
                version = 2;
              };
            };
          }
          {
            "Traefik Ligma" = {
              icon = "/images/traefik.png";
              href = "https://traefik-ligma.${baseFacts.domainName}/dashboard/";
              widget = {
                type = "traefik";
                url = "https://traefik-ligma.${baseFacts.domainName}";
              };
            };
          }
          {
            "Authentik" = {
              icon = "/images/authentik.png";
              href = "https://auth.${baseFacts.domainName}";
              server = "ligma";
              container = "authentik-server";
              widget = {
                type = "authentik";
                url = "https://auth.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_AUTHENTIK_TOKEN}}";
                version = 2;
              };
            };
          }
          {
            "Gluetun" = {
              icon = "/images/wireguard.png";
              href = "https://gluetun.${baseFacts.domainName}";
              namespace = "media";
              app = "media";
              widget = {
                type = "gluetun";
                fields = [
                  "public_ip"
                  "country"
                ];
                url = "https://gluetun.${baseFacts.domainName}";
                key = "{{HOMEPAGE_VAR_GLUETUN_TOKEN}}";
              };
            };
          }
        ];
      }
    ];
  };

  # Serve images from $HOMEPAGE_CONFIG_DIR/images/ via nginx since the
  # Next.js standalone server only serves its own bundled public/ directory.
  services.nginx.enable = true;
  services.nginx.virtualHosts."homepage-images" = {
    listen = [
      {
        addr = "127.0.0.1";
        port = 8083;
        ssl = false;
      }
    ];
    root = "/etc/homepage-dashboard";
    locations."/images/".extraConfig = "try_files $uri =404;";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      homepage = {
        rule = "Host(`homepage.${baseFacts.domainName}`)";
        entryPoints = [ "websecure" ];
        service = "homepage-svc";
        middlewares = [ "authentik" ];
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      homepage-images = {
        rule = "Host(`homepage.${baseFacts.domainName}`) && PathPrefix(`/images/`)";
        entryPoints = [ "websecure" ];
        service = "homepage-images-svc";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
      homepage-outpost = {
        rule = "Host(`homepage.${baseFacts.domainName}`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls = {
          certResolver = "letsencrypt";
          domains = [ { main = "*.${baseFacts.domainName}"; } ];
        };
      };
    };
    services.homepage-images-svc.loadBalancer.servers = [
      { url = "http://localhost:8083"; }
    ];
    services.homepage-svc.loadBalancer.servers = [
      { url = "http://localhost:8082"; }
    ];
  };

  ligma.dnsRecords."homepage.${baseFacts.domainName}".value = hosts.ligma;
}
