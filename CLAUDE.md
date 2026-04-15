# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a NixOS flake-based system configuration for a single production host (`ligma`) running on Proxmox. Key features: ephemeral root (tmpfs), full disk encryption (LUKS+ZFS), SOPS secrets, and impermanence.

## Common Commands

**Apply configuration changes to the running system (run on ligma):**
```bash
nh os switch --refresh
```
The `--refresh` flag pulls the latest flake from GitHub before building. Alternatively:
```bash
sudo nixos-rebuild switch --flake .#ligma
```

**Check flake without building:**
```bash
nix flake check
```

**Deploy/provision a new host from scratch:**
```bash
./nixos_install.sh <ip/hostname> ligma
```

**Refresh SOPS keys** (after adding/changing age keys):
```bash
./sops_refresh_key.sh
```

**Edit an encrypted secrets file:**
```bash
sops hosts/ligma/secrets.yaml
```

**Build the minimal ISO for Proxmox:**
```bash
./proxmox_nixos_iso.sh
```

**Create the Proxmox VM:**
```bash
./proxmox_ligma.sh
```

## Architecture

### Flake Structure

- **`flake.nix`** — Defines two outputs: `nixosConfigurations.ligma` (production) and `nixosConfigurations.minimaliso` (bootstrap ISO). Inputs: nixpkgs (25.11), disko, impermanence, sops-nix.
- **`common/`** — Modules applied to all hosts via `common/default.nix`.
- **`hosts/ligma/`** — Host-specific config, disk layout, and secrets.
- **`modules/`** — Reusable custom modules (currently: podman).

### Ephemeral Root + Impermanence

Root `/` is a tmpfs (wiped on reboot). Persistent state lives in `/persist` (ZFS dataset on `zroot`). SSH host keys, systemd state, logs, and podman storage are explicitly persisted via the impermanence module. Any new service needing persistent state must declare it explicitly.

### Disk Layout (`hosts/ligma/disko-config.nix`)

Two encrypted drives:
- **Main drive**: LUKS → ZFS pool `zroot` with datasets `/nix` and `/persist`, plus 1G EFI boot partition.
- **Storage drive**: LUKS → ZFS pool `zstorage` with `/ligma` dataset (NFS-exported).

### Secrets (`hosts/ligma/sops.nix`, `.sops.yaml`)

Age-based encryption with two recipients: the host's SSH key (`&hosts_ligma`) and the user key (`&makifun`). Host decrypts via `/persist/etc/ssh/ssh_host_ed25519_key` at runtime. To add a new secret: edit `secrets.yaml` with `sops`, then reference it in a `sops.nix`.

### Pre-boot LUKS Unlock

`common/boot.nix` configures initrd SSH on port 2222 with a separate ED25519 key (stored in SOPS). After `nixos_install.sh` deploys, it connects to port 2222 to unlock LUKS before the system fully boots.

### Network / Firewall

SSH restricted to `10.10.10.0/24`. NFS exported to same subnet. NFTables firewall. IPv6 disabled globally. Only ports 80, 443, and 2049 (NFS) open externally.

### Auto-upgrade

`hosts/ligma/default.nix` enables `system.autoUpgrade` pulling from the GitHub flake. Changes pushed to the repo will be automatically applied.

### Services (`hosts/ligma/apps/`)

| File | Service | Notes |
|---|---|---|
| `traefik.nix` | Traefik reverse proxy | Handles TLS termination for all apps |
| `authentik.nix` | Authentik SSO | Port 9000; PostgreSQL on zstorage |
| `forgejo.nix` | Forgejo + Actions runner | Port 3010; SSH on 22222; waits for Authentik on boot |
| `vaultwarden.nix` | Vaultwarden | Password manager |
| `homepage.nix` | Homepage dashboard | Port 8082; nginx on 8083 serves `/images/` from `/etc/homepage-dashboard/` |
| `graylog.nix` | Graylog 7 log management | Port 9099; three Podman containers on `graylog_network`: MongoDB 8, Graylog-datanode 7, Graylog 7 |

### Traefik + Authentik integration

The `authentik` forwardAuth middleware (defined in `traefik.nix`) adds SSO to any router.
The Authentik embedded outpost (port 9000) injects response headers (lowercase, e.g.
`x-authentik-username`) which Traefik copies to the upstream request via `authResponseHeaders`.

**Graylog uses a three-router priority split** (`graylog.nix`) to support both browser SSO
and Terraform/API token access on the same domain:

| Router | Priority | Rule | Middleware | Purpose |
|--------|----------|------|------------|---------|
| `graylog-outpost` | 30 | `Host + PathPrefix(/outpost.goauthentik.io)` | none | Authentik post-login callback |
| `graylog-basic-auth` | 10 | `Host + HeaderRegexp(Authorization, ^Basic .+)` | none | Terraform API token access (bypasses SSO) |
| `graylog` | 1 | `Host` (catch-all) | `authentik` | Browser SSO — header injected for Trusted Header Auth |

`GRAYLOG_TRUSTED_PROXIES` is set in the Graylog container environment so Graylog trusts
the `X-authentik-username` header forwarded from Traefik. The REST API does not support
trusted header auth (by design) — only the web UI.

### Podman

`modules/podman.nix` configures Podman. Container images use the default location (`/var/lib/containers`), which is persisted via impermanence.
