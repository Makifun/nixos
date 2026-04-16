{ pkgs, lib, ... }:
let
  # renovate: datasource=docker depName=registry
  registryTag = "2";
  base = "/var/lib/distribution";

  # One Distribution instance per upstream registry.
  # Each gets its own port, storage directory, and subdomain.
  registries = {
    dockerhub = { port = 5001; upstream = "https://registry-1.docker.io"; };
    ghcr      = { port = 5002; upstream = "https://ghcr.io";               };
    lscr      = { port = 5003; upstream = "https://lscr.io";               };
    quay      = { port = 5004; upstream = "https://quay.io";               };
  };

  mkConfig = upstream: builtins.toJSON {
    version = "0.1";
    log.level = "info";
    storage = {
      filesystem.rootdirectory = "/var/lib/registry";
      delete.enabled = true;
    };
    http.addr = ":5000";
    proxy.remoteurl = upstream;
  };
in
{
  # ---------------------------------------------------------------------------
  # Config files — one per instance, mounted read-only into each container.
  # ---------------------------------------------------------------------------
  environment.etc = lib.mapAttrs' (name: cfg:
    lib.nameValuePair "distribution/${name}/config.json" { text = mkConfig cfg.upstream; }
  ) registries;

  # ---------------------------------------------------------------------------
  # Storage directories
  # ---------------------------------------------------------------------------
  systemd.tmpfiles.rules = lib.mapAttrsToList (name: _:
    "d '${base}/${name}' 0755 root root - -"
  ) registries;

  environment.persistence."/persist".directories = lib.mapAttrsToList (name: _: {
    directory = "${base}/${name}";
    user      = "root";
    group     = "root";
    mode      = "0755";
  }) registries;

  # ---------------------------------------------------------------------------
  # Containers — one per upstream, listening on localhost only.
  # Podman mirrors are configured to hit 127.0.0.1:<port> directly (no TLS).
  # External access (e.g. from jonny) goes through Traefik subdomains below.
  # ---------------------------------------------------------------------------
  virtualisation.oci-containers.containers = lib.mapAttrs' (name: cfg:
    lib.nameValuePair "dist-${name}" {
      image   = "docker.io/library/registry:${registryTag}";
      ports   = [ "127.0.0.1:${toString cfg.port}:5000" ];
      volumes = [
        "/etc/distribution/${name}/config.json:/etc/docker/registry/config.yml:ro"
        "${base}/${name}:/var/lib/registry"
      ];
    }
  ) registries;

  # ---------------------------------------------------------------------------
  # Garbage collection — runs daily at 06:00.
  # Stops each container, runs `registry garbage-collect --delete-untagged`,
  # then restarts. Takes ~5-10 seconds per instance.
  # ---------------------------------------------------------------------------
  systemd.services.distribution-gc = {
    description = "Distribution Registry garbage collection";
    serviceConfig = { Type = "oneshot"; };
    path = [ pkgs.podman pkgs.systemd ];
    script =
      let
        names    = builtins.attrNames registries;
        stopAll  = lib.concatMapStringsSep "\n" (n:
          "systemctl stop podman-dist-${n}.service || true") names;
        gcAll    = lib.concatMapStringsSep "\n" (n: ''
          echo "GC: ${n}"
          podman run --rm \
            -v /etc/distribution/${n}/config.json:/etc/docker/registry/config.yml:ro \
            -v ${base}/${n}:/var/lib/registry \
            docker.io/library/registry:${registryTag} \
            garbage-collect /etc/docker/registry/config.yml --delete-untagged=true \
            || true
        '') names;
        startAll = lib.concatMapStringsSep "\n" (n:
          "systemctl start podman-dist-${n}.service || true") names;
      in ''
        ${stopAll}
        ${gcAll}
        ${startAll}
      '';
  };

  systemd.timers.distribution-gc = {
    description = "Daily Distribution Registry garbage collection at 06:00";
    wantedBy    = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 06:00:00";
      Persistent  = true;
    };
  };

  # ---------------------------------------------------------------------------
  # Traefik — <name>.mirror.makifun.se per instance.
  # Covered by the existing *.makifun.se wildcard cert.
  # Restricted to RFC-1918 + loopback — mirrors should not be open to the world.
  # ---------------------------------------------------------------------------
  services.traefik.dynamicConfigOptions.http = {
    middlewares."mirror-lan-only".ipAllowList.sourceRange = [
      "10.10.10.0/24"
    ];
    routers = lib.mapAttrs' (name: cfg:
      lib.nameValuePair "dist-${name}" {
        rule        = "Host(`${name}.mirror.makifun.se`)";
        entryPoints = [ "websecure" ];
        service     = "dist-${name}-svc";
        middlewares = [ "mirror-lan-only" ];
        tls.certResolver = "letsencrypt";
      }
    ) registries;
    services = lib.mapAttrs' (name: cfg:
      lib.nameValuePair "dist-${name}-svc" {
        loadBalancer.servers = [{ url = "http://127.0.0.1:${toString cfg.port}"; }];
      }
    ) registries;
  };
}
