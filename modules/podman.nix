{ pkgs, ... }:
{
  # Trust all podman bridge interfaces so aardvark-dns can bind on each
  # network's gateway and containers can query DNS. These are host-only
  # bridges — external traffic cannot arrive on podman* interfaces.
  networking.firewall.extraInputRules = ''
    iifname "podman*" accept comment "trust all podman bridge interfaces"
  '';

  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/containers";
      user = "root";
      group = "root";
      mode = "0750";
    }
  ];

  # ---------------------------------------------------------------------------
  # Registry mirrors — route pulls through the local Distribution cache first.
  # Uses localhost ports directly (no TLS overhead for on-host pulls).
  # Podman falls back to the upstream registry if the mirror is unreachable.
  # External hosts (e.g. jonny) use <name>.mirror.makifun.se instead.
  # ---------------------------------------------------------------------------
  environment.etc."containers/registries.conf.d/distribution-mirrors.conf".text = ''
    [[registry]]
    prefix   = "docker.io"
    location = "docker.io"
    [[registry.mirror]]
    location = "dockerhub.mirror.makifun.se"

    [[registry]]
    prefix   = "ghcr.io"
    location = "ghcr.io"
    [[registry.mirror]]
    location = "ghcr.mirror.makifun.se"

    [[registry]]
    prefix   = "lscr.io"
    location = "lscr.io"
    [[registry.mirror]]
    location = "lscr.mirror.makifun.se"

    [[registry]]
    prefix   = "quay.io"
    location = "quay.io"
    [[registry.mirror]]
    location = "quay.mirror.makifun.se"
  '';

  virtualisation = {
    containers = {
      enable = true;
    };
    podman = {
      enable = true;
      dockerCompat = true;
      # Enable the socket so tools like beszel-agent can query container stats.
      # Creates /run/podman/podman.sock (group: podman) and symlinks /run/docker.sock.
      dockerSocket.enable = true;
      defaultNetwork.settings.dns_enabled = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };

  # autoPrune only removes dangling (untagged) images; prune ALL unused images weekly.
  systemd.services.podman-image-prune = {
    description = "Podman: prune all unused images";
    serviceConfig = {
      Type = "oneshot";
    };
    path = [ pkgs.podman ];
    script = "podman image prune -af";
  };

  systemd.timers.podman-image-prune = {
    description = "Weekly Podman image prune";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 07:30:00";
      Persistent = true;
    };
  };
}
