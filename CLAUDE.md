# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Public repo

This repo is public on GitHub. Keep code comments and docs short. Do not add
internal addresses, network topology, setup narratives, or operational
runbooks here. Detailed notes live in the private Obsidian vault in the
homelab repo (`vault/`); start with the `nixos repo reference` note there.

## Overview

NixOS flake for the homelab hosts:

- **ligma** — main services host (Traefik, Authentik, Forgejo, monitoring, and more).
- **playma** — media host (Plex, Jellyfin, rclone `/cloud` mount, Samba).
- **minimaliso** — install ISO.

Root `/` is tmpfs on every host (impermanence). Persistent state must be
declared explicitly; app data lives on each host's data disk.

## Commands

Pre-commit sequence (mandatory for every Nix change):

```bash
nixfmt <changed-file>.nix
nix flake check
git commit
```

```bash
nh os switch --refresh            # apply on a host (pulls the flake from GitHub)
sops hosts/<host>/secrets.yaml    # edit a host's secrets
./sops_refresh_key.sh             # re-encrypt after key changes
./nixos_install.sh <ip> <host>    # provision a new host
```

## Layout

- `flake.nix` — outputs, plus `baseFacts` and `hosts` passed to every module
  via `specialArgs`.
- `common/` — modules for all hosts, auto-imported by `common/default.nix`.
- `modules/` — shared opt-in modules (rclone, samba).
- `hosts/<host>/` — host config, `disko-config.nix`, `secrets.yaml`, `apps/`.
- `CHANGELOG.md` — flake-input and package history, written by
  `.github/workflows/update-flake-inputs.yml`.

## Conventions

- Use `baseFacts.domainName` for domains and `hosts.<name>` for addresses.
  Never hard-code either.
- Pushing to `main` deploys automatically (`system.autoUpgrade`). A new SOPS
  key must be in `secrets.yaml` before the Nix change that uses it is
  pushed, or activation fails.
- Secrets: `sops.secrets.<name>.sopsFile = ../secrets.yaml;` in the app file.
- Services run as Podman containers (`virtualisation.oci-containers`).
- Web apps are reached through ligma's Traefik. An app on another host gets
  a `hosts/ligma/apps/traefik-<app>-<host>.nix` route, and its port on that
  host is opened only to ligma via `networking.firewall.extraInputRules`.
- Authentik forwardAuth is the default for web apps. Apps with their own
  OIDC login (Jellyfin, Gotify, Beszel, Technitium) have no forwardAuth.

## Renovate

Image tags are updated by the Renovate GitHub app via a regex manager. Put
the annotation above a `let` binding that holds only the tag:

```nix
let
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.14.1";
in
```

An annotation above a full `image = "registry/name:tag"` line is silently
skipped. `lscr.io/linuxserver/*` images need a `versioning` rule in
`renovate.json` when their tag format isn't `x.y.z` (see plex and jellyfin).
