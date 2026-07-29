{
  domain,
  hosts,
  lan,
  lib,
  pkgs,
  ...
}:
let
  # renovate: datasource=docker depName=registry
  registryTag = "3.1";
  base = "/ligma/distribution";

  # One Distribution instance per upstream registry.
  # Each gets its own port, storage directory, and subdomain.
  registries = {
    dockerhub = {
      port = 5001;
      debugPort = 5011;
      upstream = "https://registry-1.docker.io";
    };
    ghcr = {
      port = 5002;
      debugPort = 5012;
      upstream = "https://ghcr.io";
    };
    lscr = {
      port = 5003;
      debugPort = 5013;
      upstream = "https://lscr.io";
    };
    quay = {
      port = 5004;
      debugPort = 5014;
      upstream = "https://quay.io";
    };
  };

  mkConfig =
    upstream:
    builtins.toJSON {
      version = "0.1";
      log.level = "info";
      storage = {
        filesystem.rootdirectory = "/var/lib/registry";
        delete.enabled = true;
        cache = {
          blobdescriptor = "inmemory";
          blobdescriptorSize = 10000;
        };
      };
      http = {
        addr = ":5000";
        debug = {
          addr = ":5010";
          prometheus = {
            enabled = true;
            path = "/metrics";
          };
        };
      };
      proxy.remoteurl = upstream;
    };
in
{
  # ---------------------------------------------------------------------------
  # Config files — one per instance, mounted read-only into each container.
  # ---------------------------------------------------------------------------
  environment.etc = lib.mapAttrs' (
    name: cfg: lib.nameValuePair "distribution/${name}/config.json" { text = mkConfig cfg.upstream; }
  ) registries;

  # ---------------------------------------------------------------------------
  # Storage directories
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = lib.mapAttrsToList (
    name: _: "d '${base}/${name}' 0755 root root - -"
  ) registries;

  # ---------------------------------
  # Containers — one per upstream
  # ---------------------------------
  virtualisation.oci-containers.containers = lib.mapAttrs' (
    name: cfg:
    lib.nameValuePair "dist-${name}" {
      image = "docker.io/library/registry:${registryTag}";
      ports = [
        "127.0.0.1:${toString cfg.port}:5000"
        "127.0.0.1:${toString cfg.debugPort}:5010"
      ];
      environment = {
        OTEL_SDK_DISABLED = "true";
      };
      volumes = [
        "/etc/distribution/${name}/config.json:/etc/distribution/config.yml:ro"
        "${base}/${name}:/var/lib/registry"
      ];
    }
  ) registries;

  # ---------------------------------------------
  # Garbage collection — runs daily at 06:00.
  # ---------------------------------------------
  systemd.services.distribution-gc = {
    description = "Distribution Registry garbage collection";
    serviceConfig = {
      Type = "oneshot";
    };
    path = [
      pkgs.podman
      pkgs.systemd
    ];
    script =
      let
        names = builtins.attrNames registries;
        stopAll = lib.concatMapStringsSep "\n" (n: "systemctl stop podman-dist-${n}.service || true") names;
        gcAll = lib.concatMapStringsSep "\n" (n: ''
          echo "GC: ${n}"
          podman run --rm \
            -v /etc/distribution/${n}/config.json:/etc/distribution/config.yml:ro \
            -v ${base}/${n}:/var/lib/registry \
            docker.io/library/registry:${registryTag} \
            garbage-collect /etc/distribution/config.yml --delete-untagged=true \
            || true
        '') names;
        startAll = lib.concatMapStringsSep "\n" (
          n: "systemctl start podman-dist-${n}.service || true"
        ) names;
      in
      ''
        ${stopAll}
        ${gcAll}
        ${startAll}
      '';
  };

  systemd.timers.distribution-gc = {
    description = "Weekly Distribution Registry garbage collection (Sunday 06:00)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 06:00:00";
      Persistent = true;
    };
  };

  # ----------------------------------------------------
  # Traefik — <name>.mirror.${domain} per instance.
  # ----------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    middlewares."mirror-lan-only".ipAllowList.sourceRange = [ lan ];
    routers = lib.mapAttrs' (
      name: cfg:
      lib.nameValuePair "dist-${name}" {
        rule = "Host(`${name}.mirror.${domain}`)";
        entryPoints = [ "websecure" ];
        service = "dist-${name}-svc";
        middlewares = [ "mirror-lan-only" ];
        tls.certResolver = "letsencrypt";
      }
    ) registries;
    services = lib.mapAttrs' (
      name: cfg:
      lib.nameValuePair "dist-${name}-svc" {
        loadBalancer.servers = [ { url = "http://127.0.0.1:${toString cfg.port}"; } ];
      }
    ) registries;
  };

  ligma.dnsRecords = lib.mapAttrs' (
    name: _: lib.nameValuePair "${name}.mirror.${domain}" { value = hosts.ligma; }
  ) registries;
}
