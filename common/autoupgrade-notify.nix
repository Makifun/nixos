{ config, pkgs, ... }:
{
  sops.secrets.nixos-upgrade-gotify-token = {
    format = "yaml";
    sopsFile = ../hosts + "/${config.networking.hostName}/secrets.yaml";
  };

  systemd.services."nixos-upgrade".unitConfig = {
    OnSuccess = [ "nixos-upgrade-notify@success.service" ];
    OnFailure = [ "nixos-upgrade-notify@failure.service" ];
  };

  systemd.services."nixos-upgrade-notify@" = {
    description = "Gotify notification for nixos-upgrade (%i)";
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = "token:${config.sops.secrets.nixos-upgrade-gotify-token.path}";
      Environment = "STATUS=%i";
    };
    path = [ pkgs.curl pkgs.coreutils pkgs.gnused pkgs.systemd ];
    script = ''
      set -u
      token="$(cat "$CREDENTIALS_DIRECTORY/token")"
      generation="$(readlink /nix/var/nix/profiles/system 2>/dev/null | sed -n 's/^.*system-\([0-9]\+\)-link$/\1/p')"
      nixos_version="$(/run/current-system/sw/bin/nixos-version 2>/dev/null || echo unknown)"
      if [ "$STATUS" = "success" ]; then
        title="${config.networking.hostName} upgrade ok"
        prio=3
        msg="Generation: $generation
NixOS: $nixos_version"
      else
        title="${config.networking.hostName} upgrade FAILED"
        prio=8
        journal="$(journalctl -u nixos-upgrade.service -n 40 --no-pager 2>&1 | tail -c 3500)"
        msg="Generation: $generation
NixOS: $nixos_version

$journal"
      fi
      curl -fsS -X POST "https://gotify.makifun.se/message?token=$token" \
        -F "title=$title" \
        -F "message=$msg" \
        -F "priority=$prio"
    '';
  };
}
