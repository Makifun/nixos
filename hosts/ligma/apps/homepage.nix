{ config, ... }:
{
  # Authentik API token for the homepage widget.
  # Retrieve from Terraform: tofu output -raw homepage_token
  # Add to secrets.yaml: homepage-env: "HOMEPAGE_VAR_AUTHENTIK_TOKEN=<token>"
  sops.secrets.homepage-env = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Images are served from $HOMEPAGE_CONFIG_DIR/images/ (/etc/homepage-dashboard/images/).
  # Add files to hosts/ligma/homepage_images/ and they will appear at /images/<file> in homepage.
  environment.etc."homepage-dashboard/images".source = ../homepage_images;

  # The Podman socket (group: podman) is needed for the ligma docker connection.
  # Repeat the required fields so the merge satisfies NixOS user validation.
  users.users.homepage-dashboard = {
    isSystemUser = true;
    group        = "homepage-dashboard";
    extraGroups  = [ "podman" ];
  };
  users.groups.homepage-dashboard = {};

  services.homepage-dashboard = {
    enable = true;
    listenPort = 8082;
    allowedHosts = "localhost:8082,127.0.0.1:8082,homepage.makifun.se";
    environmentFiles = [ config.sops.secrets.homepage-env.path ];

    settings = {
      layout = [
        { Media     = { style = "column"; }; }
        { Downloads = { style = "column"; }; }
        { DVR       = { style = "column"; }; }
        { DVR4K     = { style = "column"; }; }
        { Calendar  = { style = "column"; }; }
        { Utilities = { style = "column"; columns = 1; }; }
        { Network   = { style = "column"; columns = 1; }; }
        { Server    = { style = "column"; columns = 1; }; }
      ];
      headerStyle      = "boxed";
      color            = "slate";
      theme            = "dark";
      hideVersion      = true;
      background       = "/images/background.png";
      backgroundOpacity = 0.9;
      disableCollapse  = true;
    };

    widgets = [
      { resources = { label = "System"; cpu = true; memory = true; uptime = true; }; }
      { resources = { label = "/"; disk = "/"; }; }
      { resources = { label = "/persist"; disk = "/persist"; }; }
      { resources = { label = "/ligma"; disk = "/ligma"; }; }
      { unifi_console = {
          url      = "https://{{HOMEPAGE_VAR_UNIFI_URL}}";
          username = "{{HOMEPAGE_VAR_UNIFI_USERNAME}}";
          password = "{{HOMEPAGE_VAR_UNIFI_PASSWORD}}";
        };
      }
      { openmeteo = {
          label     = "{{HOMEPAGE_VAR_OPENMETEO_LABEL}}";
          latitude  = "{{HOMEPAGE_VAR_OPENMETEO_LATITUDE}}";
          longitude = "{{HOMEPAGE_VAR_OPENMETEO_LONGITUDE}}";
          units     = "metric";
          cache     = 5;
        };
      }
      { datetime = {
          locale = "sv";
          format = { dateStyle = "long"; timeStyle = "short"; };
        };
      }
    ];

    docker = {
      jonny = { host = "{{HOMEPAGE_VAR_SOCKET_PROXY}}"; port = 2375; };
      ligma  = { socket = "/run/podman/podman.sock"; };
    };

    services = [
      { "Media" = [
          { "Plex" = {
              icon      = "plex.png";
              href      = "https://app.plex.tv";
              server    = "jonny";
              container = "{{HOMEPAGE_VAR_PLEX_CONTAINER}}";
              widget = {
                type   = "plex";
                fields = [ "streams" "movies" "tv" ];
                url    = "https://{{HOMEPAGE_VAR_PLEX_URL}}";
                key    = "{{HOMEPAGE_VAR_PLEX_TOKEN}}";
              };
            };
          }
          { "Tautulli" = {
              icon      = "tautulli.png";
              href      = "https://{{HOMEPAGE_VAR_TAUTULLI_URL}}";
              server    = "jonny";
              container = "tautulli";
              widget = {
                type              = "tautulli";
                url               = "https://{{HOMEPAGE_VAR_TAUTULLI_URL}}";
                key               = "{{HOMEPAGE_VAR_TAUTULLI_TOKEN}}";
                enableUser        = true;
                showEpisodeNumber = true;
              };
            };
          }
          { "Tracearr" = {
              icon      = "/images/tracearr.png";
              href      = "https://{{HOMEPAGE_VAR_TRACEARR_URL}}";
              server    = "jonny";
              container = "tracearr";
            };
          }
          { "Seerr" = {
              icon      = "jellyseerr.png";
              href      = "https://{{HOMEPAGE_VAR_SEERR_URL}}";
              server    = "jonny";
              container = "seerr";
              widget = {
                type   = "jellyseerr";
                fields = [ "pending" "approved" "available" "processing" ];
                url    = "https://{{HOMEPAGE_VAR_SEERR_URL}}";
                key    = "{{HOMEPAGE_VAR_SEERR_TOKEN}}";
              };
            };
          }
        ];
      }

      { "Downloads" = [
          { "NZBget" = {
              icon      = "nzbget.png";
              href      = "https://{{HOMEPAGE_VAR_NZBGET_URL}}";
              server    = "jonny";
              container = "nzbget";
              widget = {
                type     = "nzbget";
                url      = "https://{{HOMEPAGE_VAR_NZBGET_URL}}";
                username = "{{HOMEPAGE_VAR_NZBGET_USERNAME}}";
                password = "{{HOMEPAGE_VAR_NZBGET_PASSWORD}}";
              };
            };
          }
          { "qBittorrent" = {
              icon      = "qbittorrent.png";
              href      = "https://{{HOMEPAGE_VAR_QUI_URL}}";
              server    = "jonny";
              container = "qbittorrent";
              widget = {
                type                = "qbittorrent";
                fields              = [ "leech" "download" "seed" "upload" ];
                url                 = "https://{{HOMEPAGE_VAR_QBITTORRENT_URL}}";
                enableLeechProgress = true;
              };
            };
          }
          { "autobrr" = {
              icon      = "autobrr.png";
              href      = "https://{{HOMEPAGE_VAR_AUTOBRR_URL}}";
              server    = "jonny";
              container = "autobrr";
              widget = {
                type   = "autobrr";
                fields = [ "approvedPushes" "rejectedPushes" "filters" "indexers" ];
                url    = "https://{{HOMEPAGE_VAR_AUTOBRR_URL}}";
                key    = "{{HOMEPAGE_VAR_AUTOBRR_TOKEN}}";
              };
            };
          }
        ];
      }

      { "DVR" = [
          { "Sonarr" = {
              icon      = "sonarr.png";
              href      = "https://{{HOMEPAGE_VAR_SONARR_URL}}";
              server    = "jonny";
              container = "sonarr";
              widget = {
                type        = "sonarr";
                fields      = [ "wanted" "queued" "series" ];
                url         = "https://{{HOMEPAGE_VAR_SONARR_URL}}";
                key         = "{{HOMEPAGE_VAR_SONARR_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          { "Radarr" = {
              icon      = "radarr.png";
              href      = "https://{{HOMEPAGE_VAR_RADARR_URL}}";
              server    = "jonny";
              container = "radarr";
              widget = {
                type        = "radarr";
                fields      = [ "wanted" "missing" "queued" "movies" ];
                url         = "https://{{HOMEPAGE_VAR_RADARR_URL}}";
                key         = "{{HOMEPAGE_VAR_RADARR_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          { "Bazarr" = {
              icon      = "bazarr.png";
              href      = "https://{{HOMEPAGE_VAR_BAZARR_URL}}";
              server    = "jonny";
              container = "bazarr";
              widget = {
                type = "bazarr";
                url  = "https://{{HOMEPAGE_VAR_BAZARR_URL}}";
                key  = "{{HOMEPAGE_VAR_BAZARR_TOKEN}}";
              };
            };
          }
        ];
      }

      { "DVR4K" = [
          { "Sonarr4K" = {
              icon      = "/images/sonarr4k.png";
              href      = "https://{{HOMEPAGE_VAR_SONARR4K_URL}}";
              server    = "jonny";
              container = "sonarr4k";
              widget = {
                type        = "sonarr";
                fields      = [ "wanted" "queued" "series" ];
                url         = "https://{{HOMEPAGE_VAR_SONARR4K_URL}}";
                key         = "{{HOMEPAGE_VAR_SONARR4K_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          { "Radarr4K" = {
              icon      = "/images/radarr4k.png";
              href      = "https://{{HOMEPAGE_VAR_RADARR4K_URL}}";
              server    = "jonny";
              container = "radarr4k";
              widget = {
                type        = "radarr";
                fields      = [ "wanted" "missing" "queued" "movies" ];
                url         = "https://{{HOMEPAGE_VAR_RADARR4K_URL}}";
                key         = "{{HOMEPAGE_VAR_RADARR4K_TOKEN}}";
                enableQueue = true;
              };
            };
          }
          { "Bazarr4K" = {
              icon      = "/images/bazarr4k.png";
              href      = "https://{{HOMEPAGE_VAR_BAZARR4K_URL}}";
              server    = "jonny";
              container = "bazarr4k";
              widget = {
                type = "bazarr";
                url  = "https://{{HOMEPAGE_VAR_BAZARR4K_URL}}";
                key  = "{{HOMEPAGE_VAR_BAZARR4K_TOKEN}}";
              };
            };
          }
        ];
      }

      { "Calendar" = [
          { "Calendar" = {
              widget = {
                type      = "calendar";
                maxEvents = 100;
                showTime  = true;
                integrations = [
                  { type = "sonarr"; service_group = "DVR"; service_name = "Sonarr"; }
                  { type = "radarr"; service_group = "DVR"; service_name = "Radarr"; }
                ];
              };
            };
          }
        ];
      }

      { "Utilities" = [
          { "Miniflux" = {
              icon      = "/images/miniflux.svg";
              href      = "https://{{HOMEPAGE_VAR_MINIFLUX_URL}}";
              server    = "jonny";
              container = "miniflux";
              widget = {
                type = "miniflux";
                url  = "https://{{HOMEPAGE_VAR_MINIFLUX_URL}}";
                key  = "{{HOMEPAGE_VAR_MINIFLUX_TOKEN}}";
              };
            };
          }
          { "Home Assistant" = {
              icon      = "home-assistant.png";
              href      = "https://{{HOMEPAGE_VAR_HOMEASSISTANT_URL}}";
              server    = "jonny";
              container = "homeassistant";
              widget = {
                type = "homeassistant";
                url  = "https://{{HOMEPAGE_VAR_HOMEASSISTANT_URL}}";
                key  = "{{HOMEPAGE_VAR_HOMEASSISTANT_TOKEN}}";
              };
            };
          }
          { "Forgejo" = {
              icon      = "forgejo.png";
              href      = "https://{{HOMEPAGE_VAR_FORGEJO_URL}}";
              server    = "jonny";
              container = "forgejo";
              widget = {
                type   = "gitea";
                fields = [ "none" ];
                url    = "https://{{HOMEPAGE_VAR_FORGEJO_URL}}";
                key    = "{{HOMEPAGE_VAR_FORGEJO_TOKEN}}";
              };
            };
          }
          { "Filebrowser" = {
              icon      = "filebrowser.png";
              href      = "https://{{HOMEPAGE_VAR_FILEBROWSER_URL}}";
              server    = "jonny";
              container = "filebrowser";
            };
          }
          { "s3manager" = {
              icon      = "/images/s3man.png";
              href      = "https://{{HOMEPAGE_VAR_S3MANAGER_URL}}";
              server    = "jonny";
              container = "s3manager";
            };
          }
          { "Vaultwarden" = {
              icon      = "vaultwarden.png";
              href      = "https://{{HOMEPAGE_VAR_VAULTWARDEN_URL}}";
            };
          }
          { "Gotify" = {
              icon      = "gotify.png";
              href      = "https://{{HOMEPAGE_VAR_GOTIFY_URL}}";
              server    = "jonny";
              container = "gotify";
            };
          }
          { "Apprise" = {
              icon      = "apprise.png";
              href      = "https://{{HOMEPAGE_VAR_APPRISE_URL}}";
              server    = "jonny";
              container = "apprise-api";
            };
          }
          { "Prowlarr" = {
              icon      = "prowlarr.png";
              href      = "https://{{HOMEPAGE_VAR_PROWLARR_URL}}";
              server    = "jonny";
              container = "prowlarr";
            };
          }
          { "MediaInfo" = {
              icon      = "/images/mediainfo.png";
              href      = "https://{{HOMEPAGE_VAR_MEDIAINFO_URL}}";
              server    = "jonny";
              container = "mediainfo";
            };
          }
          { "Privatebin" = {
              icon      = "privatebin.png";
              href      = "https://{{HOMEPAGE_VAR_PRIVATEBIN_URL}}";
              server    = "jonny";
              container = "privatebin";
            };
          }
          { "Kasmcord" = {
              icon      = "discord.png";
              href      = "https://{{HOMEPAGE_VAR_KASMCORD_URL}}";
              server    = "jonny";
              container = "kasmcord";
            };
          }
          { "discord-rich-presence-plex" = {
              icon      = "discord.png";
              server    = "jonny";
              container = "drpp";
            };
          }
          { "Rclone" = {
              icon = "rclone.png";
              href = "https://{{HOMEPAGE_VAR_RCLONE_URL}}";
            };
          }
        ];
      }

      { "Network" = [
          { "OPNsense" = {
              icon = "opnsense.png";
              href = "https://{{HOMEPAGE_VAR_OPNSENSE_URL}}";
              widget = {
                type     = "opnsense";
                url      = "https://{{HOMEPAGE_VAR_OPNSENSE_URL}}";
                username = "{{HOMEPAGE_VAR_OPNSENSE_USERNAME}}";
                password = "{{HOMEPAGE_VAR_OPNSENSE_PASSWORD}}";
              };
            };
          }
          { "Adguard" = {
              icon = "adguard-home.png";
              href = "https://{{HOMEPAGE_VAR_ADGUARD_URL}}";
              widget = {
                type     = "adguard";
                url      = "https://{{HOMEPAGE_VAR_ADGUARD_URL}}";
                username = "{{HOMEPAGE_VAR_ADGUARD_USERNAME}}";
                password = "{{HOMEPAGE_VAR_ADGUARD_PASSWORD}}";
              };
            };
          }
          { "Unifi Controller" = {
              icon = "unifi.png";
              href = "https://{{HOMEPAGE_VAR_UNIFI_URL}}";
              server    = "ligma";
              container = "unifi";
              widget = {
                type     = "unifi";
                url      = "https://{{HOMEPAGE_VAR_UNIFI_URL}}";
                username = "{{HOMEPAGE_VAR_UNIFI_USERNAME}}";
                password = "{{HOMEPAGE_VAR_UNIFI_PASSWORD}}";
              };
            };
          }
        ];
      }

      { "Server" = [
          { "Proxmox" = {
              icon = "proxmox.png";
              href = "https://{{HOMEPAGE_VAR_PROXMOX_URL}}";
              widget = {
                type     = "proxmox";
                fields   = [ "vms" "resources.cpu" "resources.mem" ];
                url      = "https://{{HOMEPAGE_VAR_PROXMOX_URL}}";
                username = "{{HOMEPAGE_VAR_PROXMOX_USERNAME}}";
                password = "{{HOMEPAGE_VAR_PROXMOX_PASSWORD}}";
              };
            };
          }
          { "Kopia" = {
              icon = "kopia.png";
              href = "https://{{HOMEPAGE_VAR_KOPIA_URL}}";
              widget = {
                type         = "kopia";
                url          = "https://{{HOMEPAGE_VAR_KOPIA_URL}}";
                username     = "{{HOMEPAGE_VAR_KOPIA_USERNAME}}";
                password     = "{{HOMEPAGE_VAR_KOPIA_PASSWORD}}";
                snapshotHost = "jonny";
                snapshotPath = "/mnt/container-backup";
              };
            };
          }
          { "Jonny Beszel" = {
              icon      = "/images/beszel.svg";
              href      = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
              server    = "jonny";
              container = "beszel-agent";
              widget = {
                type     = "beszel";
                fields   = [ "cpu" "memory" "disk" "network" ];
                url      = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_JONNY}}";
                version  = 2;
              };
            };
          }
          { "Ligma Beszel" = {
              icon      = "/images/beszel.svg";
              href      = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
              server    = "ligma";
              container = "beszel";
              widget = {
                type     = "beszel";
                fields   = [ "cpu" "memory" "disk" "network" ];
                url      = "https://{{HOMEPAGE_VAR_BESZEL_URL}}";
                username = "{{HOMEPAGE_VAR_BESZEL_USERNAME}}";
                password = "{{HOMEPAGE_VAR_BESZEL_PASSWORD}}";
                systemId = "{{HOMEPAGE_VAR_BESZEL_SYSTEMID_LIGMA}}";
                version  = 2;
              };
            };
          }
          { "Portainer" = {
              icon      = "portainer.png";
              href      = "https://{{HOMEPAGE_VAR_PORTAINER_URL}}";
              server    = "jonny";
              container = "portainer";
              widget = {
                type   = "portainer";
                fields = [ "running" "stopped" "total" ];
                url    = "https://{{HOMEPAGE_VAR_PORTAINER_URL}}";
                env    = 1;
                key    = "{{HOMEPAGE_VAR_PORTAINER_TOKEN}}";
              };
            };
          }
          { "Authentik" = {
              icon = "authentik.png";
              href = "https://{{HOMEPAGE_VAR_AUTHENTIK_URL}}";
              widget = {
                type    = "authentik";
                url     = "https://{{HOMEPAGE_VAR_AUTHENTIK_URL}}";
                key     = "{{HOMEPAGE_VAR_AUTHENTIK_TOKEN}}";
                version = 2;
              };
            };
          }
          { "Graylog" = {
              icon = "graylog.png";
              server    = "ligma";
              container = "graylog";
              href = "https://{{HOMEPAGE_VAR_GRAYLOG_URL}}";
            };
          }
          { "Traefik Jonny" = {
              icon = "traefik.png";
              server    = "jonny";
              container = "traefik";
              href = "https://{{HOMEPAGE_VAR_TRAEFIK_JONNY_URL}}/dashboard/";
              widget = {
                type = "traefik";
                url  = "https://{{HOMEPAGE_VAR_TRAEFIK_JONNY_URL}}";
              };
            };
          }
          { "Traefik Ligma" = {
              icon = "traefik.png";
              href = "https://{{HOMEPAGE_VAR_TRAEFIK_LIGMA_URL}}/dashboard/";
              widget = {
                type = "traefik";
                url  = "https://{{HOMEPAGE_VAR_TRAEFIK_LIGMA_URL}}";
              };
            };
          }
          { "Gluetun" = {
              icon      = "/images/wireguard.png";
              href      = "https://{{HOMEPAGE_VAR_GLUETUN_URL}}";
              server    = "jonny";
              container = "vpn";
              widget = {
                type   = "gluetun";
                fields = [ "public_ip" "country" ];
                url    = "https://{{HOMEPAGE_VAR_GLUETUN_URL}}";
                key    = "{{HOMEPAGE_VAR_GLUETUN_TOKEN}}";
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
    listen = [{ addr = "127.0.0.1"; port = 8083; ssl = false; }];
    root = "/etc/homepage-dashboard";
    locations."/images/".extraConfig = "try_files $uri =404;";
  };

  services.traefik.dynamicConfigOptions.http = {
    routers = {
      homepage = {
        rule        = "Host(`homepage.makifun.se`)";
        entryPoints = [ "websecure" ];
        service     = "homepage-svc";
        middlewares = [ "authentik" ];
        tls.certResolver = "letsencrypt";
      };
      homepage-images = {
        rule        = "Host(`homepage.makifun.se`) && PathPrefix(`/images/`)";
        entryPoints = [ "websecure" ];
        service     = "homepage-images-svc";
        tls.certResolver = "letsencrypt";
      };
      homepage-outpost = {
        rule        = "Host(`homepage.makifun.se`) && PathPrefix(`/outpost.goauthentik.io`)";
        entryPoints = [ "websecure" ];
        service     = "authentik-embedded-outpost";
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
}
