{ config, pkgs, ... }:
let
  threshold = 50;
  python = pkgs.python3.withPackages (ps: [
    ps.plexapi
    ps.requests
  ]);
  script = pkgs.writeScript "plex-trash" ''
    #!${python}/bin/python3
    import json, logging, os, sys
    import requests
    from plexapi.server import PlexServer

    logging.basicConfig(level=logging.INFO, format="%(levelname)-8s %(message)s", stream=sys.stdout)
    log = logging.getLogger(__name__)
    THRESHOLD = ${toString threshold}


    def gotify_notify(url, token, title, message, priority=5):
        r = requests.post(
            f"{url}/message",
            headers={"X-Gotify-Key": token},
            json={"title": title, "message": message, "priority": priority},
            timeout=10,
        )
        r.raise_for_status()


    def trash_count(plex, section):
        t = 4 if section.TYPE == "show" else 1
        return len(plex.fetchItems(f"/library/sections/{section.key}/all?type={t}&trash=1"))


    def main():
        plex_token   = os.environ["PLEX_TOKEN"]
        gotify_token = os.environ["GOTIFY_TOKEN"]
        plex_url     = os.environ["PLEX_URL"]
        gotify_url   = os.environ["GOTIFY_URL"]
        libraries    = json.loads(os.environ["PLEX_LIBRARIES"])

        plex = PlexServer(plex_url, plex_token)
        cleared, notify, total = [], [], 0

        for name in libraries:
            try:
                section = plex.library.section(name)
                count = trash_count(plex, section)
            except Exception as e:
                log.error("%s: query failed — %s", name, e)
                continue

            total += count
            if count == 0:
                log.info("%s: no trash", name)
            elif count < THRESHOLD:
                try:
                    section.emptyTrash()
                    cleared.append((name, count))
                    log.info("%s: cleared %d", name, count)
                except Exception as e:
                    log.error("%s: emptyTrash failed — %s", name, e)
            else:
                notify.append((name, count))
                log.warning("%s: %d — above threshold (%d)", name, count, THRESHOLD)

        log.info("total trash: %d", total)

        if notify:
            lines = "\n".join(f"  {n}: {c}" for n, c in notify)
            try:
                gotify_notify(
                    gotify_url, gotify_token, "Plex Trash Alert",
                    f"Above threshold ({THRESHOLD}):\n{lines}\n\nTotal: {total}",
                )
                log.info("gotify notified (%d %s)", len(notify), "library" if len(notify) == 1 else "libraries")
            except Exception as e:
                log.error("gotify failed — %s", e)

        if cleared:
            log.info("cleared: %s", ", ".join(f"{n} ({c})" for n, c in cleared))


    if __name__ == "__main__":
        main()
  '';
in
{
  sops.secrets = {
    plex-trash-plex-token.sopsFile = ../secrets.yaml;
    plex-trash-gotify-token.sopsFile = ../secrets.yaml;
    plex-trash-plex-url.sopsFile = ../secrets.yaml;
    plex-trash-gotify-url.sopsFile = ../secrets.yaml;
    plex-trash-libraries.sopsFile = ../secrets.yaml;
  };

  sops.templates."plex-trash.env".content = ''
    PLEX_TOKEN=${config.sops.placeholder."plex-trash-plex-token"}
    GOTIFY_TOKEN=${config.sops.placeholder."plex-trash-gotify-token"}
    PLEX_URL=${config.sops.placeholder."plex-trash-plex-url"}
    GOTIFY_URL=${config.sops.placeholder."plex-trash-gotify-url"}
    PLEX_LIBRARIES=${config.sops.placeholder."plex-trash-libraries"}
  '';

  systemd.services.plex-trash = {
    description = "Plex trash destroyer";
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.sops.templates."plex-trash.env".path;
      ExecStart = "${script}";
    };
  };

  systemd.timers.plex-trash = {
    description = "Plex trash destroyer timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
    };
  };
}
