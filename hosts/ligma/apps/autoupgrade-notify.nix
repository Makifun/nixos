{ config, pkgs, ... }:
{
  # Gotify app token for nixos-upgrade notifications.
  # Add to secrets.yaml as: nixos-upgrade-gotify-token: "<token>"
  sops.secrets.nixos-upgrade-gotify-token = {
    format = "yaml";
    sopsFile = ../secrets.yaml;
  };

  # Attach notifier units to the autoUpgrade-generated service.
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
    path = [ pkgs.curl pkgs.coreutils pkgs.systemd ];
    script = ''
      set -u
      token="$(cat "$CREDENTIALS_DIRECTORY/token")"
      gen="$(readlink -f /run/current-system | sed 's|.*/||')"
      if [ "$STATUS" = "success" ]; then
        title="ligma upgrade ok"
        prio=3
        msg="New generation: $gen"
      else
        title="ligma upgrade FAILED"
        prio=8
        msg="$(journalctl -u nixos-upgrade.service -n 40 --no-pager 2>&1 | tail -c 3500)"
      fi
      curl -fsS -X POST "https://gotify.makifun.se/message?token=$token" \
        -F "title=$title" \
        -F "message=$msg" \
        -F "priority=$prio"
    '';
  };
}
