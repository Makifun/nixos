{ config, ... }:
{
  # Authentik API token for the homepage widget.
  # Retrieve from Terraform: tofu output -raw homepage_token
  # Add to secrets.yaml: homepage-env: "HOMEPAGE_VAR_AUTHENTIK_TOKEN=<token>"
  sops.secrets.homepage-env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Kubeconfig for sugma k8s cluster (homepage SA token).
  # After Flux applies k8s/infra/homepage-rbac, build the kubeconfig:
  #   TOKEN=$(kubectl get secret homepage-token -n homepage -o jsonpath='{.data.token}' | base64 -d)
  # Then add to secrets.yaml: sops hosts/ligma/secrets.yaml
  #   homepage-kubeconfig: |
  #     apiVersion: v1
  #     kind: Config
  #     clusters:
  #     - cluster:
  #         insecure-skip-tls-verify: true
  #         server: https://10.10.10.29:6443
  #       name: sugma
  #     contexts:
  #     - context:
  #         cluster: sugma
  #         user: homepage
  #       name: homepage@sugma
  #     current-context: homepage@sugma
  #     users:
  #     - name: homepage
  #       user:
  #         token: <TOKEN>
  sops.secrets.homepage-kubeconfig = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
    owner = "homepage-dashboard";
  };

  # Images are served from $HOMEPAGE_CONFIG_DIR/images/ (/etc/homepage-dashboard/images/).
  # Add files to hosts/ligma/homepage_images/ and they will appear at /images/<file> in homepage.
  environment.etc."homepage-dashboard/images".source = ../homepage_images;

  # The Podman socket (group: podman) is needed for the ligma docker connection.
  # Repeat the required fields so the merge satisfies NixOS user validation.
  users.users.homepage-dashboard = {
    isSystemUser = true;
    group = "homepage-dashboard";
    extraGroups = [ "podman" ];
  };
  users.groups.homepage-dashboard = { };

  systemd.services.homepage-dashboard.environment.KUBECONFIG =
    config.sops.secrets.homepage-kubeconfig.path;

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "localhost:8082,127.0.0.1:8082,homepage.makifun.se";
    environmentFiles = [ config.sops.secrets.homepage-env.path ];

    kubernetes = {
      mode = "default";
      gateway = true;
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
        resources = {
          label = "/cloud";
          disk = "/cloud";
          expanded = true;
        };
      }
      {
        resources = {
          label = "/nicememe";
          disk = "/nicememe";
          expanded = true;
        };
      }
      {
        resources = {
          label = "/slowmeme";
          disk = "/slowmeme";
          expanded = true;
        };
      }
      {
        unifi_console = {
          url = "https://{{HOMEPAGE_VAR_UNIFI_URL}}";
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

    docker = {
      jonny = {
        host = "{{HOMEPAGE_VAR_SOCKET_PROXY}}";
        port = 2375;
      };
      ligma = {
        socket = "/run/podman/podman.sock";
      };
    };

    services = [
      {
        "Media" = [
          {
            "Plex" = {
              icon = "/images/plex.png";
              href = "https://app.plex.tv";
              server = "jonny";
              container = "{{HOMEPAGE_VAR_PLEX_CONTAINER}}";
              widget = {
                type = "plex";
                fields = [
                  "streams"
                  "movies"
                  "tv"
                ];
                url = "https://{{HOMEPAGE_VAR_PLEX_URL}}";
                key = "{{HOMEPAGE_VAR_PLEX_TOKEN}}";
              };
            };
          }
          {
            "Tracearr" = {
              icon = "/images/tracearr.png";
              href = "https://{{HOMEPAGE_VAR_TRACEARR_URL}}";
              namespace = "tracearr";
              app = "tracearr";
              widget = {
                type = "tracearr";
                url = "https://{{HOMEPAGE_VAR_TRACEARR_URL}}";
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
              href = "https://{{HOMEPAGE_VAR_SEERR_URL}}";
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
                url = "https://{{HOMEPAGE_VAR_SEERR_URL}}";
                key = "{{HOMEPAGE_VAR_SEERR_TOKEN}}";
              };
            };
          }
          {
            "SeerrOld" = {
              icon = "/images/seerr.png";
              href = "https://{{HOMEPAGE_VAR_SEERROLD_URL}}";
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
                url = "https://{{HOMEPAGE_VAR_SEERROLD_URL}}";
                key = "{{HOMEPAGE_VAR_SEERROLD_TOKEN}}";
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
              href = "https://{{HOMEPAGE_VAR_NZBGET_URL}}";
              namespace = "nzbget";
              app = "nzbget";
              widget = {
                type = "nzbget";
                url = "https://{{HOMEPAGE_VAR_NZBGET_URL}}";
                username = "{{HOMEPAGE_VAR_NZBGET_USERNAME}}";
                password = "{{HOMEPAGE_VAR_NZBGET_PASSWORD}}";
              };
            };
          }
          {
            "qBittorrent" = {
              icon = "/images/qbittorrent.png";
              href = "https://{{HOMEPAGE_VAR_QUI_URL}}";
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
                url = "https://{{HOMEPAGE_VAR_QBITTORRENT_URL}}";
                enableLeechProgress = true;
              };
            };
          }
          {
            "autobrr" = {
              icon = "/images/autobrr.png";
              href = "https://{{HOMEPAGE_VAR_AUTOBRR_URL}}";
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
                url = "https://{{HOMEPAGE_VAR_AUTOBRR_URL}}";
                key = "{{HOMEPAGE_VAR_AUTOBRR_TOKEN}}";
              };
            };
          }
          {
            "Prowlarrpg" = {
              icon = "/images/prowlarr.png";
              href = "https://{{HOMEPAGE_VAR_PROWLARRPG_URL}}";
              namespace = "media";
              app = "media";
              widget = {
                type = "prowlarr";
                url = "https://{{HOMEPAGE_VAR_PROWLARRPG_URL}}";
                key = "{{HOMEPAGE_VAR_PROWLARRPG_TOKEN}}";
              };
            };
          }
        ];
      }

      {
        "DVR" = [
          {
            "Sonarrpg" = {
              icon = "/images/sonarr.png";
              href = "https://{{HOMEPAGE_VAR_SONARRPG_URL}}";
              namespace = "sonarrpg";
              app = "sonarrpg";
              widget = {
                type = "sonarr";
                fields = [
                  "wanted"
                  "queued"
                  "series"
                ];
                url = "https://{{HOMEPAGE_VAR_SONARRPG_URL}}";
                key = "{{HOMEPAGE_VAR_SONARRPG_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Radarrpg" = {
              icon = "/images/radarr.png";
              href = "https://{{HOMEPAGE_VAR_RADARRPG_URL}}";
              namespace = "radarrpg";
              app = "radarrpg";
              widget = {
                type = "radarr";
                fields = [
                  "wanted"
                  "missing"
                  "queued"
                  "movies"
                ];
                url = "https://{{HOMEPAGE_VAR_RADARRPG_URL}}";
                key = "{{HOMEPAGE_VAR_RADARRPG_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Bazarr" = {
              icon = "/images/bazarr.png";
              href = "https://{{HOMEPAGE_VAR_BAZARR_URL}}";
              namespace = "bazarr";
              app = "bazarr";
              widget = {
                type = "bazarr";
                url = "https://{{HOMEPAGE_VAR_BAZARR_URL}}";
                key = "{{HOMEPAGE_VAR_BAZARR_TOKEN}}";
              };
            };
          }
        ];
      }

      {
        "DVR4K" = [
          {
            "Sonarr4Kpg" = {
              icon = "/images/sonarr4k.png";
              href = "https://{{HOMEPAGE_VAR_SONARR4KPG_URL}}";
              namespace = "sonarr4kpg";
              app = "sonarr4kpg";
              widget = {
                type = "sonarr";
                fields = [
                  "wanted"
                  "queued"
                  "series"
                ];
                url = "https://{{HOMEPAGE_VAR_SONARR4KPG_URL}}";
                key = "{{HOMEPAGE_VAR_SONARR4KPG_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Radarr4Kpg" = {
              icon = "/images/radarr4k.png";
              href = "https://{{HOMEPAGE_VAR_RADARR4KPG_URL}}";
              namespace = "radarr4kpg";
              app = "radarr4kpg";
              widget = {
                type = "radarr";
                fields = [
                  "wanted"
                  "missing"
                  "queued"
                  "movies"
                ];
                url = "https://{{HOMEPAGE_VAR_RADARR4KPG_URL}}";
                key = "{{HOMEPAGE_VAR_RADARR4KPG_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          {
            "Bazarr4K" = {
              icon = "/images/bazarr4k.png";
              href = "https://{{HOMEPAGE_VAR_BAZARR4K_URL}}";
              namespace = "bazarr4k";
              app = "bazarr4k";
              widget = {
                type = "bazarr";
                url = "https://{{HOMEPAGE_VAR_BAZARR4K_URL}}";
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
                    service_name = "Sonarrpg";
                  }
                  {
                    type = "radarr";
                    service_group = "DVR";
                    service_name = "Radarrpg";
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
              href = "https://{{HOMEPAGE_VAR_MINIFLUX_URL}}";
              namespace = "miniflux";
              app = "miniflux";
              widget = {
                type = "miniflux";
                url = "https://{{HOMEPAGE_VAR_MINIFLUX_URL}}";
                key = "{{HOMEPAGE_VAR_MINIFLUX_TOKEN}}";
              };
            };
          }
          {
            "Home Assistant" = {
              icon = "/images/home-assistant.png";
              href = "https://{{HOMEPAGE_VAR_HOMEASSISTANT_URL}}";
              namespace = "homeassistant";
              app = "homeassistant";
              widget = {
                type = "homeassistant";
                url = "https://{{HOMEPAGE_VAR_HOMEASSISTANT_URL}}";
                key = "{{HOMEPAGE_VAR_HOMEASSISTANT_TOKEN}}";
              };
            };
          }
          {
            "HAVC" = {
              icon = "/images/havc.png";
              href = "https://{{HOMEPAGE_VAR_HAVC_URL}}";
              namespace = "homeassistant";
              app = "homeassistant";
            };
          }
          {
            "Forgejo" = {
              icon = "/images/forgejo.png";
              href = "https://{{HOMEPAGE_VAR_FORGEJO_URL}}";
              widget = {
                type = "gitea";
                fields = [
                  "repositories"
                  "issues"
                  "pulls"
                ];
                url = "https://{{HOMEPAGE_VAR_FORGEJO_URL}}";
                key = "{{HOMEPAGE_VAR_FORGEJO_TOKEN}}";
              };
            };
          }
          {
            "Vaultwarden" = {
              icon = "/images/vaultwarden.png";
              href = "https://{{HOMEPAGE_VAR_VAULTWARDEN_URL}}";
              server = "ligma";
              container = "vaultwarden";
            };
          }
          {
            "Filebrowser" = {
              icon = "/images/filebrowser.png";
              href = "https://{{HOMEPAGE_VAR_FILEBROWSER_URL}}";
              namespace = "filebrowser";
              app = "filebrowser";
            };
          }
          {
            "s3manager" = {
              icon = "/images/s3man.png";
              href = "https://{{HOMEPAGE_VAR_S3MANAGER_URL}}";
              namespace = "s3manager";
              app = "s3manager";
            };
          }
          {
            "pgAdmin" = {
              icon = "/images/pgadmin.png";
              href = "https://{{HOMEPAGE_VAR_PGADMIN_URL}}";
              server = "ligma";
              container = "pgadmin";
            };
          }
          {
            "Profilarr" = {
              icon = "/images/profilarr.png";
              href = "https://{{HOMEPAGE_VAR_PROFILARR_URL}}";
              namespace = "profilarr";
              app = "profilarr";
            };
          }
          {
            "Gotify" = {
              icon = "/images/gotify.png";
              href = "https://{{HOMEPAGE_VAR_GOTIFY_URL}}";
              server = "ligma";
              container = "gotify";
            };
          }
          {
            "Apprise" = {
              icon = "/images/apprise.png";
              href = "https://{{HOMEPAGE_VAR_APPRISE_URL}}";
              server = "ligma";
              container = "apprise";
            };
          }
          {
            "MediaInfo" = {
              icon = "/images/mediainfo.png";
              href = "https://{{HOMEPAGE_VAR_MEDIAINFO_URL}}";
              namespace = "mediainfo";
              app = "mediainfo";
            };
          }
          {
            "PrivateBin" = {
              icon = "/images/privatebin.png";
              href = "https://{{HOMEPAGE_VAR_PRIVATEBIN_URL}}";
              namespace = "privatebin";
              app = "privatebin";
            };
          }
          {
            "KasmCord" = {
              icon = "/images/discord.png";
              href = "https://{{HOMEPAGE_VAR_KASMCORD_URL}}";
              namespace = "kasmcord";
              app = "kasmcord";
            };
          }
          {
            "Rclone Ligma" = {
              icon = "/images/rclone.png";
              href = "https://{{HOMEPAGE_VAR_RCLONELIGMA_URL}}";
            };
          }
          {
            "Rclone Storma" = {
              icon = "/images/rclone.png";
              href = "https://{{HOMEPAGE_VAR_RCLONESTORMA_URL}}";
            };
          }
          {
            "Rclone Playma" = {
              icon = "/images/rclone.png";
              href = "https://{{HOMEPAGE_VAR_RCLONEPLAYMA_URL}}";
            };
          }
        ];
      }

      {
        "Network" = [
          {
            "OPNsense" = {
              icon = "/images/opnsense.png";
              href = "https://{{HOMEPAGE_VAR_OPNSENSE_URL}}";
              widget = {
                type = "opnsense";
                url = "https://{{HOMEPAGE_VAR_OPNSENSE_URL}}";
                username = "{{HOMEPAGE_VAR_OPNSENSE_USERNAME}}";
                password = "{{HOMEPAGE_VAR_OPNSENSE_PASSWORD}}";
              };
            };
          }
          {
            "Technitium" = {
              icon = "/images/technitium.png";
              href = "https://{{HOMEPAGE_VAR_TECHNITIUM_URL}}";
              widget = {
                type = "technitium";
                fields = [
                  "totalQueries"
                  "totalAuthoritative"
                  "totalCached"
                  "totalBlocked"
                ];
                url = "https://{{HOMEPAGE_VAR_TECHNITIUM_URL}}";
                key = "{{HOMEPAGE_VAR_TECHNITIUM_TOKEN}}";
              };
            };
          }
          {
            "Unifi Controller" = {
              icon = "/images/unifi.png";
              href = "https://{{HOMEPAGE_VAR_UNIFI_URL}}";
              server = "ligma";
              container = "unifi";
              widget = {
                type = "unifi";
                url = "https://{{HOMEPAGE_VAR_UNIFI_URL}}";
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
              href = "https://{{HOMEPAGE_VAR_WATCHYOURLAN_URL}}";
              widget = {
                type = "customapi";
                url = "https://{{HOMEPAGE_VAR_WATCHYOURLAN_URL}}/api/status/";
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
              href = "https://{{HOMEPAGE_VAR_PROXMOX_URL}}";
              widget = {
                type = "proxmox";
                fields = [
                  "vms"
                  "resources.cpu"
                  "resources.mem"
                ];
                url = "https://{{HOMEPAGE_VAR_PROXMOX_URL}}";
                username = "{{HOMEPAGE_VAR_PROXMOX_USERNAME}}";
                password = "{{HOMEPAGE_VAR_PROXMOX_PASSWORD}}";
              };
            };
          }
          {
            "Omni" = {
              icon = "/images/sidero.png";
              href = "https://{{HOMEPAGE_VAR_OMNI_URL}}";
              server = "ligma";
              container = "omni";
            };
          }
          {
            "Kopia" = {
              icon = "/images/kopia.png";
              href = "https://{{HOMEPAGE_VAR_KOPIA_URL}}";
              widget = {
                type = "kopia";
                url = "https://{{HOMEPAGE_VAR_KOPIA_URL}}";
                username = "{{HOMEPAGE_VAR_KOPIA_USERNAME}}";
                password = "{{HOMEPAGE_VAR_KOPIA_PASSWORD}}";
                snapshotHost = "jonny";
                snapshotPath = "/mnt/container-backup";
              };
            };
          }
          {
            "Backrest Ligma" = {
              icon = "/images/backrest.png";
              href = "https://{{HOMEPAGE_VAR_BACKREST_LIGMA_URL}}";
              server = "ligma";
              container = "backrest";
              widget = {
                type = "backrest";
                url = "http://127.0.0.1:9898";
              };
            };
          }
          {
            "Backrest Bofa" = {
              icon = "/images/backrest.png";
              href = "https://{{HOMEPAGE_VAR_BACKREST_BOFA_URL}}";
              widget = {
                type = "backrest";
                url = "http://10.10.10.14:9898";
              };
            };
          }
          {
            "Beszel Ligma" = {
              icon = "/images/beszel.svg";
              href = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
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
                url = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_LIGMA}}";
                version = 2;
              };
            };
          }
          {
            "Beszel Bofa" = {
              icon = "/images/beszel.svg";
              href = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
              widget = {
                type = "beszel";
                fields = [
                  "cpu"
                  "memory"
                  "disk"
                  "network"
                ];
                url = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_BOFA}}";
                version = 2;
              };
            };
          }
          {
            "Beszel Playma" = {
              icon = "/images/beszel.svg";
              href = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
              widget = {
                type = "beszel";
                fields = [
                  "cpu"
                  "memory"
                  "disk"
                  "network"
                ];
                url = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_PLAYMA}}";
                version = 2;
              };
            };
          }
          {
            "Beszel Storma" = {
              icon = "/images/beszel.svg";
              href = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
              widget = {
                type = "beszel";
                fields = [
                  "cpu"
                  "memory"
                  "disk"
                  "network"
                ];
                url = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_STORMA}}";
                version = 2;
              };
            };
          }
          {
            "Grafana" = {
              icon = "/images/grafana.png";
              href = "https://{{HOMEPAGE_VAR_GRAFANA_URL}}";
            };
          }
          {
            "Traefik Jonny" = {
              icon = "/images/traefik.png";
              server = "jonny";
              container = "traefik";
              href = "https://{{HOMEPAGE_VAR_TRAEFIK_JONNY_URL}}/dashboard/";
              widget = {
                type = "traefik";
                url = "https://{{HOMEPAGE_VAR_TRAEFIK_JONNY_URL}}";
              };
            };
          }
          {
            "Traefik Ligma" = {
              icon = "/images/traefik.png";
              href = "https://{{HOMEPAGE_VAR_TRAEFIK_LIGMA_URL}}/dashboard/";
              widget = {
                type = "traefik";
                url = "https://{{HOMEPAGE_VAR_TRAEFIK_LIGMA_URL}}";
              };
            };
          }
          {
            "Authentik" = {
              icon = "/images/authentik.png";
              href = "https://{{HOMEPAGE_VAR_AUTHENTIK_URL}}";
              server = "ligma";
              container = "authentik-server";
              widget = {
                type = "authentik";
                url = "https://{{HOMEPAGE_VAR_AUTHENTIK_URL}}";
                key = "{{HOMEPAGE_VAR_AUTHENTIK_TOKEN}}";
                version = 2;
              };
            };
          }
          {
            "Gluetun" = {
              icon = "/images/wireguard.png";
              href = "https://{{HOMEPAGE_VAR_GLUETUN_URL}}";
              namespace = "media";
              app = "media";
              widget = {
                type = "gluetun";
                fields = [
                  "public_ip"
                  "country"
                ];
                url = "https://{{HOMEPAGE_VAR_GLUETUN_URL}}";
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
        rule = "Host(`homepage.makifun.se`)";
        entryPoints = [ "websecure" ];
        service = "homepage-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      homepage-images = {
        rule = "Host(`homepage.makifun.se`) && PathPrefix(`/images/`)";
        entryPoints = [ "websecure" ];
        service = "homepage-images-svc";
        tls.certResolver = "letsencrypt";
      };
      homepage-outpost = {
        rule = "Host(`homepage.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service = "authentik-embedded-outpost";
        tls.certResolver = "letsencrypt";
      };
    };
    services.homepage-images-svc.loadBalancer.servers = [
      { url = "http://localhost:8083"; }
    ];
    services.homepage-svc.loadBalancer.servers = [
      { url = "http://localhost:8082"; }
    ];
  };

  ligma.dnsRecords."homepage.makifun.se".value = "10.10.10.13";
}
