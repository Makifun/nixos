# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based system configuration for three hosts:

- **ligma** — production services host on Proxmox; ephemeral root (tmpfs), LUKS+ZFS, SOPS, impermanence.
- **bofa** (VM 888, 10.10.10.14) — dedicated database host on Proxmox; ephemeral root (tmpfs), LUKS+XFS+LVM. Runs TimescaleDB for tracearr + all arr apps.
- **playma** (10.10.10.15) — NixOS VM on Proxmox; Plex + `/cloud` via rclone FUSE (S3 crypt remote, VFS cache on 200 G disk), re-exported via Samba to sugma (port 445, guest auth). Intel GVT-g iGPU for hardware transcoding.

## Common Commands

**Apply configuration changes to the running system (run on ligma):**
```bash
nh os switch --refresh
```
The `--refresh` flag pulls the latest flake from GitHub before building. Alternatively:
```bash
sudo nixos-rebuild switch --flake .#ligma
```

**Pre-commit sequence (mandatory for every Nix change):**
```bash
nixfmt <changed-file>.nix   # 1. format
nix flake check              # 2. validate all nixosConfigurations
git commit                   # 3. only then commit
```

**Format Nix files:**
```bash
nixfmt <file.nix>
# or format entire tree:
nixfmt **/*.nix
```

**Deploy/provision a new host from scratch:**
```bash
./nixos_install.sh <ip/hostname> ligma
./nixos_install.sh <ip/hostname> bofa
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

- **`flake.nix`** — Defines three outputs: `nixosConfigurations.ligma`, `nixosConfigurations.bofa`, and `nixosConfigurations.minimaliso`. Inputs: nixpkgs (unstable, stateVersion 25.11), disko, impermanence, sops-nix.
- **`common/`** — Modules applied to all hosts via `common/default.nix` (auto-imports all `.nix` files in the directory): boot (initrd SSH), users, sops, openssh, hardening, fail2ban, zram, autoupgrade, autoupgrade-notify, alloy. **ZFS-specific config is NOT in common** — it lives in `hosts/ligma/default.nix` only (bofa uses XFS).
- **`hosts/ligma/`** — ligma-specific config, disk layout (ZFS), and secrets.
- **`hosts/bofa/`** — bofa-specific config, disk layout (XFS+LVM), and secrets.
- **`modules/`** — Reusable custom modules (currently: podman).
- **`CHANGELOG.md`** — flake-input and package version history; `.github/workflows/update-flake-inputs.yml` prepends a dated entry on each lock update (see "Flake input updates" below).

### Ephemeral Root + Impermanence

Root `/` is a tmpfs (wiped on reboot). Persistent state lives in `/persist` (ZFS dataset on `zroot`). SSH host keys, systemd state, logs, and podman storage are explicitly persisted via the impermanence module. Any new service needing persistent state must declare it explicitly.

### Disk Layout — ligma (`hosts/ligma/disko-config.nix`)

Two encrypted drives:

- **Main drive** (`scsi-0QEMU_QEMU_HARDDISK_nixos`): LUKS → ZFS pool `zroot` with datasets `/nix` and `/persist` (refreservation: 10G), plus 1G EFI partition.
- **Storage drive** (`scsi-0QEMU_QEMU_HARDDISK_ligma`): LUKS → ZFS pool `zstorage` with `/ligma` dataset (refreservation: 5G). All app persistent data lives here.
Both drives use XFS with `noatime,nofail`. LUKS passphrases entered via initrd SSH at boot. **New VM install:** disko formats on `nixos_install.sh`. **Existing VM adding a disk:** must manually partition + luksFormat + mkfs.xfs before `nh os switch` — see comments in `disko-config.nix`.

All ZFS pools: ashift=12, autotrim=on, compression=lz4, atime=off, xattr=sa. ARC max=4 GB, min=2 GB (ligma balloon: 12 GB floor, 16 GB ceiling). Prefetch disabled (`zfs_prefetch_disable=1`).

### Disk Layout — bofa (`hosts/bofa/disko-config.nix`)

Two encrypted drives (no ZFS — lower overhead for DB workloads):

- **OS disk** (50 G, `scsi-0QEMU_QEMU_HARDDISK_nixos`): 1 G EFI + LUKS(`crypted_nixos`) → LVM `vg_nixos` → XFS `/nix` (25 G) + XFS `/persist` (~24 G). Single passphrase for both via LVM.
- **Data disk** (100 G, `scsi-0QEMU_QEMU_HARDDISK_bofa`): LUKS(`crypted_bofa`) → XFS `/bofa`. All app data lives here (postgresql, backrest, beszel).

XFS mount options: `noatime,discard`.

### Disk Layout — playma (`hosts/playma/disko-config.nix`)

Four drives, XFS throughout, root is tmpfs (impermanence module, same pattern as ligma):

- **OS disk** (50 G, `scsi-0QEMU_QEMU_HARDDISK_nixos`): 1 G EFI + LUKS(`crypted_nixos`) → LVM `vg_nixos` → XFS `/nix` (25 G) + XFS `/persist` (rest). Single passphrase for both via LVM.
- **App data disk** (100 G, `scsi-0QEMU_QEMU_HARDDISK_playma`): LUKS(`crypted_playma`) → XFS `/playma`. All app persistent data lives here.
- **Cache disk** (400 G, `scsi-0QEMU_QEMU_HARDDISK_cache`): no LUKS (regenerable) → XFS `/rclone-cache`. rclone VFS cache; `vfsCacheMaxSize` set in `apps/rclone-extra.nix` (currently 380 G, 20 G headroom).
- **Transcode disk** (50 G, `scsi-0QEMU_QEMU_HARDDISK_transcode`): no LUKS (ephemeral) → XFS `/transcode`. Plex transcoder scratch space.

**Growing a disko-managed disk after enlarging the virtual disk in Proxmox:** disko's `size = "100%"` only applies at first format — it does not live-resize an already-formatted disk. On the running host:

1. `sudo nix shell nixpkgs#gptfdisk -c sgdisk -e /dev/sdX` — relocates the GPT backup header to the new disk end (fixes the "GPT not using all space" warning).
2. Grow partition 1 to fill the disk. `parted /dev/sdX resizepart 1 100%` prompts "partition is in use, are you sure?" and does not accept a piped answer over a non-tty SSH session; use `sgdisk` delete+recreate instead, keeping the original start sector, type GUID, unique GUID, and name (`sgdisk -i 1 /dev/sdX` to read them first): `sudo nix shell nixpkgs#gptfdisk -c sgdisk -d 1 -n 1:<start>:0 -t 1:<type-guid> -u 1:<unique-guid> -c 1:'<name>' /dev/sdX`.
3. `sudo xfs_growfs <mountpoint>` — grows the live filesystem to fill the partition.

Update the disko comment and any size-derived options (e.g. `vfsCacheMaxSize` in `apps/rclone-extra.nix`) afterward to match.

### Secrets (`hosts/ligma/sops.nix`, `.sops.yaml`)

Age-based encryption with two recipients: the host's SSH key (`&hosts_ligma`) and the user key (`&makifun`). Host decrypts via `/persist/etc/ssh/ssh_host_ed25519_key` at runtime. To add a new secret: edit `secrets.yaml` with `sops`, then reference it in a `sops.nix`.

### Pre-boot LUKS Unlock

`common/boot.nix` configures initrd SSH on port 2222 with a separate ED25519 key (stored in SOPS). After `nixos_install.sh` deploys, it connects to port 2222 to unlock LUKS before the system fully boots.

### Network / Firewall

SSH restricted to `10.10.10.0/24`. NFTables firewall. IPv6 disabled globally. Traefik (80/443) reachable from `10.10.10.0/24` and `10.10.11.0/24` (WireGuard).

Note: `/cloud` is **not** exported via NFS. jonny mounts it via CIFS (Samba). Sugma apps access `/cloud` via SMB CSI (`//10.10.10.13/cloud`, guest auth).

### Auto-upgrade

`common/autoupgrade.nix` enables `system.autoUpgrade` for all hosts, pulling from `github:makifun/nixos`. Changes pushed to that repo are automatically applied with a randomised 30-min delay. Reboot window 03:00–06:00 (`allowReboot=false` means no auto-reboot outside window).

### Services (`hosts/ligma/apps/`)

| File | Service | Port | Notes |
|---|---|---|---|
| `traefik.nix` | Traefik reverse proxy | 80, 443, 8090 (dashboard) | TLS termination, Cloudflare DNS challenge, wildcards `*.makifun.se` + `*.mirror.makifun.se` (separate SANs — single-level wildcard does not cover two-level subdomains). JSON access log (`accessLog.format = "json"`) — client IPs for mirror pulls visible in Loki. ACME `resolvers` hardcoded to `1.1.1.1:53`, `8.8.8.8:53` to bypass OPNsense DNS intercept for propagation checks. Dashboard loopback only. Trusted IP: 10.10.10.1 (OPNsense HAProxy). **ACME DNS gotcha:** Technitium is both the local authoritative NS and the web UI hostname. `technitium.makifun.se` resolves to `10.10.10.13` (Traefik) in LAN — lego finds `technitium.makifun.se` as NS, resolves it, tries port 53 → "connection refused". True fix: change Technitium NS record to a hostname that resolves to `10.10.10.3` (e.g. `ns.makifun.se`) rather than the web UI proxy IP. |
| `authentik.nix` | Authentik SSO | 9000 (embedded outpost) | Three Podman containers (`authentik_network`): Redis + server + worker. Native PostgreSQL at `/ligma/ligma/authentik/postgresql`. `/run/postgresql` bind-mounted with `trust` auth. SOPS: `authentik_env`. Port 9000 is exposed to the full LAN (not loopback-only) for forwardAuth from other hosts. |
| `forgejo.nix` | Forgejo + Actions runner | 3010, SSH 22222 | `forgejo-provision` service auto-creates makifun/opnsense/renovate-bot users on every boot. Renovate token persists to `/ligma/ligma/renovate/token`. SOPS: `forgejo-admin-password`, `forgejo-admin-email`, `forgejo-oauth-secret`, `forgejo-runner-token`. |
| `vaultwarden.nix` | Vaultwarden | 8310 | OIDC via Authentik. Signup disabled. fail2ban protection. SOPS: `vaultwarden_env`. |
| `homepage.nix` | Homepage dashboard | 8082, 8083 (images) | nginx on 8083 serves `/images/` (Next.js can't serve custom public/). Connects to sugma k8s via SOPS kubeconfig. SOPS: `homepage-env`, `homepage-kubeconfig`. |
| `monitoring.nix` | Prometheus + Grafana | 9090, 9100, 3000 | 30d retention. Grafana OIDC via Authentik, role from `groups` claim. Alerting: Authentik login success/failure → Gotify webhook. Dashboards (from `grafana_dashboards/`): rclone, registry, rclone-transfers, podman-containers, node-exporter-full, opnsense, proxmox, postgres (CNPG `general-apps` + `tracearr` TimescaleDB, sourced from sugma's `cnpg`/`tracearr-db` Alloy scrape jobs — see `sugma/CLAUDE.md`). Scrape jobs: rclone, prometheus, distribution (debug ports 5011-5014), loki, alloy, opnsense-node, opnsense, pve (relay: `?target=proxmoxifun.makifun.se` → `127.0.0.1:9221/pve`). SOPS: `grafana-secret-key`, `grafana-oauth-secret`, `grafana-gotify-token`. |
| `pve-exporter.nix` | prometheus-pve-exporter | 9221 | Proxmox API metrics for Grafana proxmox dashboard. Config written to `/run/pve-exporter.yml` by `pve-exporter-config.service` (oneshot, `chmod 444` — container runs non-root). `verify_ssl: true` (Proxmox has LE cert). SOPS: `proxmox-pve-token-value`. One-time Proxmox setup: create user `prometheus@pve` + API token `prometheus` with PVEAuditor role; **apply the role to both user and token** (privilege separation = intersection — token role alone is not enough). `pveum aclmod / --users 'prometheus@pve' --roles PVEAuditor --propagate 1`. |
| `backrest.nix` | Backrest backup manager | 9898 | Restic-backed S3. Backs up `/ligma/ligma` (`:ro`). `/ligma/restore` mounted rw for restore staging. Schedule: 04:00 UTC. Prune: 05:00 UTC. SOPS: `backrest-restic-password`, `backrest-repo-uri`, `backrest-aws-access-key-id`, `backrest-aws-secret-access-key`, `backrest-gotify-token`. |
| `rclone.nix` | rclone S3 FUSE mount | 6969 (RC), 6970 (metrics) | Shared module currently used by playma. Mounts S3 crypt remote at `/cloud`. VFS cache at `/rclone-cache`. **Primary cloud host is now playma (10.10.10.15).** |
| `samba.nix` | Samba/CIFS share | 445 | Exposes `/cloud` as `\\<host>\cloud`. Guest access, force user=root. `hosts allow`: jonny (10.10.10.16) + sugma nodes (10.10.10.26-28). Sugma cloud PVs point to playma (10.10.10.15). |
| `omni.nix` | Sidero Omni (Talos cluster manager) | 9999 (UI), 50180/udp (WG), 8091 (machine API), 8098/6443 (k8s proxy) | Distroless container. SAML auth via Authentik. JWT key is OpenPGP ASCII-armor (not PEM). SOPS: `omni-account-uuid`, `omni-jwt-signing-key`. |
| `gotify.nix` | Gotify push notifications | 8096 | v3 native OIDC via Authentik (`auth.makifun.se/application/o/gotify/`). Two-router split: `X-Gotify-Key` header bypass (push senders), catch-all no-middleware (Gotify handles OIDC itself). Client secret from SOPS `gotify-oidc-secret` → `/run/gotify-oidc.env` via `gotify-env-setup` oneshot. `GOTIFY_OIDC_LINK_BY_USERNAME=true` links existing local users. **Local password auth is disabled** (`GOTIFY_LOCALAUTH_ENABLED=false`, v3.1.0+) — OIDC via Authentik is the only login path; login button reads "Authentik" (`GOTIFY_OIDC_IDP_NAME`). Unaffected: all `/message?token=...` app-token pushes (autoupgrade-notify, garage-sync, watchyourlan Shoutrrr, Grafana, Backrest) — those use per-application tokens, not username/password. |
| `apprise.nix` | Apprise notification aggregator | 8097 | Three-router split: `/outpost` callback, `/notify` path (API bypass for senders), catch-all SSO. |
| `beszel-server.nix` + `common/beszel-agent.nix` | Beszel monitoring hub + agent | 8095 (hub, loopback), 45876 (agent) | Agents self-register via universal token. No Authentik forwardAuth — Beszel handles its own login via native OIDC (PocketBase admin UI, not NixOS). See "Beszel monitoring" below. |
| `distribution.nix` | OCI registry mirrors | 5001-5004 | Four instances: dockerhub (5001), ghcr (5002), lscr (5003), quay (5004). Daily GC at 06:00 UTC. LAN-only via `mirror-lan-only` ipAllowList middleware. `log.level = "info"` — HTTP request logs visible in Loki (`job=ligma-podman-dist-*`). Client IPs are NOT visible here (containers see Podman bridge `10.88.0.1`); use Traefik JSON access logs for real client IPs (`RouterName =~ "dist-.+"`). |
| `unifi.nix` | UniFi Network Application | 8443 (UI), 8080 (inform), 3478/udp (STUN), 10001/udp (discovery), 5141/udp (syslog in) | Two Podman containers (`unifi_network`): MongoDB 8 + linuxserver/unifi. Syslog on 5141 ingested by Alloy → Loki (job=ligma-unifi). UI self-signed cert — Traefik uses `insecureSkipVerify`. PUID/PGID=1000, MEM_LIMIT=1024M. |
| `watchyourlan.nix` | WatchYourLAN network presence monitor | 8840 (UI) | Lightweight ARP scanner; notifies via Shoutrrr → Gotify on new/returning devices. Host networking + NET_ADMIN/NET_RAW caps required. Config written on first boot from SOPS `watchyourlan-gotify-token`; UI changes persist (delete `config_v2.yaml` to reset). Scans `ens18` every 60s. SOPS: `watchyourlan-gotify-token`. |
| `garage.nix` | Garage S3-compatible object store | 3900 (S3 API, loopback) | Single-node (`replication_factor=1`). Data at `/ligma/garage/{data,meta}`. S3 API via Traefik at `https://s3.makifun.se` (no Authentik — S3 clients use access key auth). Admin API loopback-only (3901). RPC loopback-only (3902). No built-in web UI — use `podman exec garage /garage` for management. SOPS: `garage-rpc-secret` (`openssl rand -hex 32`), `garage-admin-token`. **Bootstrap (run once after first deploy):** `podman exec garage /garage layout assign -z dc1 -c 280G <node-id> && podman exec garage /garage layout apply --version 1`. Create buckets/keys with `podman exec garage /garage bucket create <name>` and `podman exec garage /garage key create <name>`. |
| `hosts/ligma/dns-records.nix` | DNS record module | — | Defines `ligma.dnsRecords` option. Each app sets `ligma.dnsRecords."<fqdn>".value = "<ip>"` and a `systemd.services.dns-record-<name>` oneshot runs `nsupdate` with TSIG to register the record in Technitium at `10.10.10.3`. SOPS: `technitium-tsig-key` (base64 HMAC-SHA256 secret, key name `ligma-key`). Services retry on failure until Technitium is reachable. |
| `common/autoupgrade-notify.nix` | Gotify notifier on `nixos-upgrade` | — | `OnSuccess`/`OnFailure` hooks; title uses hostname; includes generation + NixOS version; failure attaches last 40 journal lines (capped 3500 bytes). SOPS: `nixos-upgrade-gotify-token`. |
| `netbird.nix` | NetBird VPN management | 8811 (dashboard), 33073 (mgmt), 10000/10080 (signal), 33080 (relay), 3478/udp (STUN/TURN) | 5 containers on `netbird_network` (10.89.3.0/24). Coturn uses host network. Secrets in `netbird-config.service` oneshot (SOPS: `netbird-datastore-key`, `netbird-relay-secret`, `netbird-turn-password`). Authentik public PKCE OIDC (`client_id=netbird`); no forwardAuth. gRPC paths use `h2c://` backend scheme in Traefik. Dashboard: `https://netbird.makifun.se`. CLI: `netbird up --management-url https://netbird.makifun.se`. **`netbird-datastore-key` must be exactly 32 bytes** — generate with `openssl rand -base64 32` (produces 44-char base64 string; Netbird hashes it internally to 32 bytes). `openssl rand -base64 24` (32 chars) is NOT accepted. |
| `syncstorage.nix` | Firefox Sync (syncstorage-rs) | 8000 | Mozilla syncstorage-rs postgres variant. Tokenserver enabled; authenticates via Mozilla FxA OAuth (no Authentik). Two PostgreSQL DBs (`syncstorage`, `tokenserver`) owned by `syncstorage` user; provisioned by `syncstorage-db-setup.service`. Connects via Unix socket bind-mount. SOPS: `syncstorage_env` (must contain `SYNC_MASTER_SECRET=...`). Firefox client URL: `https://firefox.makifun.se/1.0/sync/1.5`. |
| `technitium.nix` | Technitium DNS Server (external) | — | Traefik proxy to Technitium LXC at `10.10.10.3`. `technitium.makifun.se` → `https://10.10.10.3:53443` (self-signed, `insecureSkipVerify`). **No Authentik forwardAuth** — Technitium handles auth via its own OIDC login (like Jellyfin); adding forwardAuth causes 404 since there is no proxy provider. `doh.makifun.se` → `http://10.10.10.3` (no auth). OIDC configured in `ligma/authentik/technitium.tf`. Sets `ligma.dnsRecords."technitium.makifun.se"`. |
| `backrest-bofa.nix` | Traefik proxy to bofa backrest | — | Routes `backrest-bofa.makifun.se` → `http://<BOFA_IP>:9898` via Authentik SSO. Replace `REPLACE_WITH_BOFA_IP` in the file with bofa's actual IP. |
| `pgadmin.nix` | PGAdmin PostgreSQL manager | 5050 | `dpage/pgadmin4:9`. Desktop mode (`SERVER_MODE=False`, no login screen — Authentik handles auth). Pre-configured servers: bofa (TimescaleDB at 10.10.10.14:5432, user=tracearr) and ligma (native PG at /run/postgresql socket, user=authentik). Data at `/ligma/ligma/pgadmin` (UID/GID 5050). Socket bind-mount: `/run/postgresql`. `ENHANCED_COOKIE_PROTECTION=False` (breaks behind reverse proxy). |

### Services (`hosts/bofa/apps/`)

| File | Service | Port | Notes |
|---|---|---|---|
| `timescaledb.nix` | TimescaleDB (Podman) | 5432 | `timescale/timescaledb-ha:pg18.1-ts2.25.0`. Data at `/bofa/bofa/postgresql`. `POSTGRES_USER=tracearr`, `POSTGRES_DB=tracearr`. Password from SOPS `timescaledb-tracearr-password` via `sops.templates."timescaledb.env"`. `max_connections=200` (raised from 100 — 8 arr apps exhaust 100 on cold-start burst). bofa has **balloon RAM** (5 GB min / 8 GB max, Proxmox). Port open to sugma nodes 10.10.10.26-28 only. SOPS: `timescaledb-tracearr-password`. |
| `backrest.nix` | Backrest backup manager | 9898 | Restic-backed S3. Backs up `/bofa/bofa`. Port 9898 open to ligma (10.10.10.13) only for Traefik proxy. Schedule: 05:00 UTC. Prune: 06:00 UTC. SOPS: same keys as ligma backrest. |
| `common/beszel-agent.nix` | Beszel agent | 45876 | Monitors bofa; reports disk usage of `/bofa` and `/persist`. Self-registers with the hub via universal token — see "Beszel monitoring" in the ligma section. |
| `pgbackweb.nix` | pgBackWeb logical backup UI | 8085 | `eduardolat/pgbackweb:0.5.1`. Web UI for scheduled pg_dump backups to Garage `pgbackweb` S3 bucket. State DB: `pgbackweb` database in the local timescaledb instance, owned by the `pgbackweb` user (`pg_read_all_data` grant). Port open to ligma only; exposed via Traefik + Authentik at `pgbackweb.makifun.se`. SOPS: `pgbackweb-encryption-key`, `pgbackweb-db-password`. Configure databases and S3 destination via the web UI (use key-value DSN format for connection strings: `host=10.88.0.1 port=5432 user=pgbackweb ...`). |

**To add a new bofa secret:** `sops hosts/bofa/secrets.yaml`, add the key, reference in the app `.nix` file.

**bofa IP:** `10.10.10.14` (MAC `2E:7A:45:73:8C:64`, static DHCP reservation recommended).

### Traefik + Authentik integration

The `authentik` forwardAuth middleware (defined in `traefik.nix`) adds SSO to any router.
The Authentik embedded outpost (port 9000) injects response headers (lowercase, e.g.
`x-authentik-username`) which Traefik copies to the upstream request via `authResponseHeaders`.

Every service protected by the `authentik` middleware also needs a second router for
`PathPrefix(/outpost.goauthentik.io)` pointing to `authentik-embedded-outpost` (no middleware)
so the post-login callback reaches the outpost.

**Three-router priority split** — used by Graylog, Gotify, and Apprise to support both browser SSO and API clients on the same domain:

| Router | Priority | Rule | Middleware | Purpose |
|--------|----------|------|------------|---------|
| `*-outpost` | 30 | `Host + PathPrefix(/outpost.goauthentik.io)` | none | Authentik post-login callback |
| `*-api` | 10 | Header match (e.g. `Authorization: Basic`, `X-Gotify-Key`) | none | API/token clients bypass SSO |
| `*` | 1 | `Host` (catch-all) | `authentik` | Browser SSO |

Graylog uses `Authorization: ^Basic .+` (Terraform API access). Gotify uses `X-Gotify-Key`. Apprise uses `PathPrefix(/notify)`.

### Journald retention

`hosts/ligma/default.nix` caps journal at **512 MB / 7 days**. Logs ship to Graylog via Vector. Vacuum manually: `journalctl --vacuum-size=512M --vacuum-time=7d`.

### Authentik (Podman containers)

Authentik runs as three containers on a dedicated `authentik_network` bridge:

| Container | Image | Role |
|---|---|---|
| `authentik-redis` | `redis:7-alpine` | Celery broker + cache |
| `authentik-server` | `ghcr.io/goauthentik/server:<tag>` | Web UI + embedded outpost (port 9000) |
| `authentik-worker` | `ghcr.io/goauthentik/server:<tag>` | Celery worker |

PostgreSQL runs as a native NixOS service at `/ligma/ligma/authentik/postgresql`. Both server and worker bind-mount `/run/postgresql` and connect via Unix socket. A `local authentik authentik trust` pg_hba rule (prepended via `lib.mkBefore`) bypasses peer auth since container UIDs don't match the OS `authentik` user.

**Renovate pin**: add `# renovate: datasource=docker depName=ghcr.io/goauthentik/server` above the `authTag` line in `authentik.nix`.

### Podman

`modules/podman.nix` configures Podman. Container images use the default location (`/var/lib/containers`), which is persisted via impermanence. All Podman bridge interfaces are trusted in the firewall (aardvark-dns). Custom networks (authentik_network, graylog_network, unifi_network) use subnets in `10.89.x.0/24`.

**DNS quirk for multi-network containers**: aardvark-dns resolves Podman container names only within the same network. Containers in different networks that need to cross-resolve each other must use `10.88.0.1` (default Podman gateway) as DNS — aardvark-dns there resolves all networks. Used by unifi_network containers.

### Omni (Sidero Talos cluster manager)

Self-hosted Omni runs as a Podman container on ligma. State (embedded etcd + SQLite) lives at `/ligma/ligma/omni/`. Auth is delegated to Authentik via SAML — no Traefik forwardAuth in front of the Omni router. The corresponding SAML provider, application, and policy binding are defined in the **authentik** repo at `omni.tf`; that must be `tofu apply`'d before deploying Omni so the metadata URL resolves.

Three SOPS secrets live in `hosts/ligma/secrets.yaml`:

| Secret | Purpose | Format |
|---|---|---|
| `omni-account-uuid` | `--account-id` (passed via `OMNI_ACCOUNT_ID`) | bare UUID string |
| `omni-jwt-signing-key` | `--private-key-source` for embedded-etcd master key encryption | **ASCII-armored OpenPGP private key** (gopenpgp), not raw PEM |
| `omni-wireguard-key` | reserved, currently unused | WG private key |

**Generate the PGP key** (one-time):

```bash
nix run nixpkgs#gnupg -- --batch --gen-key <<EOF
%no-protection
Key-Type: EDDSA
Key-Curve: ed25519
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: omni
Name-Email: omni@makifun.se
Expire-Date: 0
%commit
EOF
nix run nixpkgs#gnupg -- --armor --export-secret-keys omni@makifun.se
```

Paste the full `-----BEGIN PGP PRIVATE KEY BLOCK-----...END...` into sops as a YAML literal block (`omni-jwt-signing-key: |`). After editing the secret on a running ligma, `systemctl restart omni-prep podman-omni` to re-stage and re-load the key without a full rebuild.

**SAML quirks worth knowing** (configured in the authentik repo, not here):

- Provider `audience` must be `https://omni.makifun.se/saml/metadata` (the metadata path), not the bare host. Omni rejects any other value.
- The provider must include the default property mappings (email, name, username, uid, upn) and pin `name_id_mapping` to the email mapping — Authentik otherwise sends an empty `<saml:AttributeStatement/>` and Omni cannot identify the user.
- `--auth-saml-attribute-rules` maps Authentik's MS SOAP claim URIs (`http://schemas.xmlsoap.org/ws/2005/05/identity/claims/...`) to Omni's internal `identity` and `fullname` fields.
- `--auth-saml-url` takes the metadata URL despite its name. `--auth-saml-metadata` expects a local XML file path, not a URL.

**Other gotchas:**

- Omni's distroless image has no `/bin/sh` — entrypoint must be the binary directly, no wrapper script.
- The `--account-id` flag has no env-binding shown in `--help`, but cobra/viper auto-binds `OMNI_ACCOUNT_ID`.
- Required flags not obvious from `--help`: `--sqlite-storage-path`, `--etcd-embedded-db-path`, `--machine-api-advertised-url`. Missing flags fail with JSON-schema validation errors that name the missing config path.
- `--initial-users` re-checks on every start and seeds new admin emails. Existing users created via the UI are not touched.

### Beszel monitoring

Beszel hub (loopback port 8095, also reachable via Traefik at `beszel.makifun.se`) + agent (`common/beszel-agent.nix`, host networking, port 45876) on every flake-managed host. Agent must run on host networking to see host interfaces.

**Agents self-register via universal token** — the agent dials *out* to the hub (`HUB_URL = https://beszel.makifun.se`) and authenticates with a shared `KEY` (hub's public SSH key, same for every agent) + `TOKEN` (a permanent Universal Token, same for every agent). A new host provisioned from the flake shows up in the hub automatically; no manual "add system" step. `PORT`/`LISTEN` isn't set — that only matters for the legacy hub-initiated model (hub connects *to* the agent), which nothing uses anymore now that every agent/DaemonSet uses `HUB_URL`. The agent still binds its default `LISTEN` port (45876) internally since that's just how the binary starts up, but no firewall rule opens it — cleaned up along with `hosts/ligma/apps/beszel-extra.nix` (its only content was that now-dead rule; deleted, not just emptied).

**No Authentik forwardAuth in front of Beszel at all** — Beszel handles its own login via native OIDC (see below), same migration Gotify went through. `beszel-server.nix`'s single `beszel` router has no `authentik` middleware and no outpost-callback router; nothing gates `beszel.makifun.se` at the Traefik layer, including the agent's fixed self-registration path `/api/beszel/agent-connect` (moot now — there was never anything there to bypass once forwardAuth was dropped). The old proxy provider entry (`ligma_apps["beszel"]` + its `skip_path_regex`) was removed from the `authentik` repo's `apps.tf`.

**Native OIDC login** ([beszel.dev/guide/oauth](https://beszel.dev/guide/oauth)) — Beszel is PocketBase-backed, so unlike Gotify (env-var driven) its OAuth2 provider settings are entered by hand into Beszel's own admin UI, not NixOS. One-time setup:
1. `tofu apply` in the `authentik` repo (`beszel.tf`) to create the OAuth2 provider + application, then `tofu output -raw beszel_oauth_client_secret`.
2. In Beszel: `https://beszel.makifun.se/_/#/settings` → toggle off "Hide collection create and edit controls" → edit the `users` collection → Options tab → OAuth2 → enable → add provider → OpenID Connect, with:
   - Client ID / Client secret: from step 1
   - Auth URL: `https://auth.makifun.se/application/o/authorize/`
   - Token URL: `https://auth.makifun.se/application/o/token/`
   - User info URL: `https://auth.makifun.se/application/o/userinfo/`
3. Toggle "Hide collection create and edit controls" back on.
4. Beszel does not auto-create users from OIDC login by default — either set `USER_CREATION=true` (not currently set), or make sure the existing Beszel account's email matches the Authentik account's email so login links to it instead of failing.
5. Verify: click "authentik" on the Beszel login page, confirm it round-trips through Authentik back into Beszel.
6. Verified and now enforced: `DISABLE_PASSWORD_AUTH=true` is set on the hub container (`beszel-server.nix`) — OIDC via Authentik is the only login path, no local password fallback.

SOPS secrets in `common/secrets.yaml` (shared by every host):
- `beszel_agent_key` — hub's public SSH key. One-time bootstrap: create the hub admin account at `https://beszel.makifun.se`, add any one system in the UI to reveal the key, copy it into this secret as `KEY=<value>`.
- `beszel_universal_token` — Settings → Tokens & Fingerprints → enable Universal Token → toggle "permanent" → copy. Store as `TOKEN=<value>`.

Both secrets above are consumed directly as container `environmentFiles`, so the stored value must be the full `KEY=...`/`TOKEN=...` line, not just the bare value. Same convention for the hub-only secret below.

No port is opened for the agent at all anymore — self-registration rides Traefik's existing 443, and the legacy port-45876 firewall rules (per-agent in `common/beszel-agent.nix`, plus a LAN-wide one in the now-deleted `hosts/ligma/apps/beszel-extra.nix`) were removed once nothing used them.

**Outbound heartbeat** ([beszel.dev/guide/heartbeat](https://beszel.dev/guide/heartbeat), 0.18.4+) — the hub itself pings an external monitor (e.g. a healthchecks.io-style push URL) on an interval to prove it's alive, independent of any agent. `beszel-server.nix` sets it via `beszel_heartbeat_url` in `hosts/ligma/secrets.yaml` (hub-only, not the shared `common/secrets.yaml` — this is a hub concern, not an agent one), stored as `HEARTBEAT_URL=<value>`. `HEARTBEAT_INTERVAL`/`HEARTBEAT_METHOD` are left unset — Beszel's built-in defaults apply.

### Distribution registry mirrors

Four OCI registry mirror instances, each a `docker.io/library/registry:3` container:

| Instance | Port | Upstream |
|---|---|---|
| `dist-dockerhub` | 5001 | https://registry-1.docker.io |
| `dist-ghcr` | 5002 | https://ghcr.io |
| `dist-lscr` | 5003 | https://lscr.io |
| `dist-quay` | 5004 | https://quay.io |

Served at `{name}.mirror.makifun.se` behind `mirror-lan-only` ipAllowList middleware (10.10.10.0/24 only). Daily garbage collection at 06:00 UTC (systemd timer, stops containers → runs GC → restarts). Talos nodes and Podman are configured to pull from these mirrors. Logs filtered from Vector (OTEL disabled, debug spam suppressed).

`log.level = "info"` — pull events (HTTP GETs) appear in Loki under `job=ligma-podman-dist-*`. Distribution containers only see `10.88.0.1` (Podman bridge = Traefik) — real client IPs only available from Traefik JSON access logs. Use Loki query: `{job="ligma-syslog", unit="traefik.service"} | json | RouterName =~ "dist-.+" | RequestMethod =~ "GET|HEAD"`.

**Grafana registry dashboard** (`registry.json`) — uses `registry_proxy_*` metrics (not `registry_storage_cache_*` which track internal blob descriptor cache). Distribution v3 renamed metrics: `registry_storage_cache_total{type="Hit"}` → `registry_storage_cache_hits_total`, `{type="Request"}` → `registry_storage_cache_requests_total`. Dashboard datasource UIDs must be hardcoded (`prometheus`, `loki`) — file provisioning does not substitute `${DS_PROMETHEUS}` / `__inputs`.

### Homepage → Kubernetes integration

`homepage.nix` connects Homepage to the sugma k8s cluster for service discovery and pod metrics.

**How it works:**
- `kubernetes.mode = "default"` + `gateway = true` — enables Gateway API HTTPRoute discovery
- `KUBECONFIG` env var points to a SOPS secret rendered at runtime
- Homepage uses the `homepage` ServiceAccount (scoped read-only ClusterRole) in the `homepage` namespace on sugma

**SOPS secret `homepage-kubeconfig`** — kubeconfig YAML for the sugma cluster. Must be added to `secrets.yaml` after Flux applies `k8s/infra/homepage-rbac/` on sugma.

**One-time bootstrap** (run after `k8s/infra/homepage-rbac/` is deployed):

```bash
TOKEN=$(kubectl get secret homepage-token -n homepage -o jsonpath='{.data.token}' | base64 -d)
```

Add to `sops hosts/ligma/secrets.yaml`:

```yaml
homepage-kubeconfig: |
  apiVersion: v1
  kind: Config
  clusters:
  - cluster:
      insecure-skip-tls-verify: true
      server: https://10.10.10.29:6443
    name: sugma
  contexts:
  - context:
      cluster: sugma
      user: homepage
    name: homepage@sugma
  current-context: homepage@sugma
  users:
  - name: homepage
    user:
      token: <TOKEN>
```

The secret is rendered with `owner = "homepage-dashboard"` so the service can read it. The `KUBECONFIG` env var is injected via `systemd.services.homepage-dashboard.environment`.

**HTTPRoute auto-discovery** — annotate any HTTPRoute on sugma with:

```yaml
annotations:
  gethomepage.dev/enabled: "true"
  gethomepage.dev/name: "My App"
  gethomepage.dev/group: "Server"
  gethomepage.dev/icon: "myapp.png"
  gethomepage.dev/href: "https://myapp.makifun.se"
  gethomepage.dev/pod-selector: "app=myapp"   # matches actual pod label (not app.kubernetes.io/name)
  # optional widget:
  gethomepage.dev/widget.type: "myapp"
  gethomepage.dev/widget.url: "https://{{HOMEPAGE_VAR_MYAPP_URL}}"
  gethomepage.dev/widget.key: "{{HOMEPAGE_VAR_MYAPP_TOKEN}}"
```

`{{HOMEPAGE_VAR_*}}` substitution works in annotations. `pod-selector` must match actual pod labels — homepage defaults to `app.kubernetes.io/name=<name>` which often doesn't match.

### Auto-upgrade notifications

`common/autoupgrade-notify.nix` hooks `OnSuccess=`/`OnFailure=` on `nixos-upgrade.service` to a templated oneshot (`nixos-upgrade-notify@%i`) that posts to `https://gotify.makifun.se`. Title uses `config.networking.hostName`. Failure messages include generation number, NixOS version, and last 40 journal lines (capped at 3500 bytes). sopsFile resolves to `hosts/<hostname>/secrets.yaml` automatically. SOPS key: `nixos-upgrade-gotify-token`. Test with:

```bash
sudo systemctl start nixos-upgrade-notify@success.service
```

### Renovate

Two independent Renovate instances run against this fleet — do not confuse them:

1. **GitHub web app**, covering *this* repo's own `.nix` files. `renovate.json` in the repo root configures the GitHub Renovate web app to update container image tags in `.nix` files (see below).
2. **Self-hosted Forgejo Actions**, covering the internal Forgejo repos (`makifun/authentik`, `makifun/makiplex-bot`, `makifun/sugma`). Runs as a scheduled workflow (`.forgejo/workflows/renovate.yml`, hourly cron) in the dedicated `makifun/renovate-config` repo on `git.makifun.se`, using the existing self-hosted Forgejo Actions runner (`runs-on: nix`, job container overridden to `ghcr.io/renovatebot/renovate:<tag>`). Config lives in that repo's `renovate-config.json` (`platform: gitea`, `binarySource: install` — the job container runs as root so Renovate can self-install per-repo toolchains like Go, no manual mounting needed). Secrets `RENOVATE_TOKEN` (renovate-bot's Forgejo token) and `RENOVATE_GITHUB_TOKEN` (GitHub PAT for release notes; **not** `GITHUB_COM_TOKEN` — Forgejo rejects secret names with the `GITHUB_` prefix) are repo-level Actions secrets on `renovate-config`, since Forgejo has no user-level secrets scope (only repo/org) and `makifun` is a personal account, not an org. renovate-bot's Forgejo token is generated once by `forgejo-provision` (see `forgejo.nix`) and persisted to `/ligma/ligma/renovate/token`; to rotate, regenerate the token (`rm /ligma/ligma/renovate/token && systemctl restart forgejo-provision`) then re-push it as the `RENOVATE_TOKEN` secret on `renovate-config` via the Forgejo UI or API. This replaced an earlier standalone `renovate.nix` systemd timer + Podman one-shot on ligma (removed) — that setup ran as the unprivileged `forgejo` user and needed a manually bind-mounted Nix-provided Go toolchain for `gomod` support, which Actions' root-container default avoids.

`renovate.json` in the repo root configures the GitHub Renovate web app to update container image tags in `.nix` files.

**Custom regex manager** — matches lines annotated with `# renovate: datasource=docker depName=<image>` followed by a Nix assignment. The annotation must be in a `let` block, and the assigned value must be **only the tag** (not a full image reference):

```nix
let
  # renovate: datasource=docker depName=ghcr.io/garethgeorge/backrest
  backrestTag = "v1.14.1";
in
{
  virtualisation.oci-containers.containers.backrest = {
    image = "ghcr.io/garethgeorge/backrest:${backrestTag}";
```

**Never put the annotation above `image = "registry/name:tag"` directly.** Renovate captures the entire assignment value as `currentValue` and validates it as a docker version. A full image reference like `"ghcr.io/foo/bar:v1.2.3"` fails validation (`skipReason: invalid-value`) and the package is silently skipped.

**linuxserver.io versioning quirk** — `lscr.io/linuxserver/*` images publish historic Ubuntu release tags (`20.04.1`, `22.04.1`) that sort above application version tags under semver. `renovate.json` applies:

1. A global regex versioning rule for all `lscr.io/linuxserver/*` images (handles `version-v` prefix for nzbget and `amd64-` prefix for multi-arch tags).
2. Per-image `allowedVersions` constraints for qbittorrent (`>=5.0.0 <6.0.0`), prowlarr (`>=2.0.0 <3.0.0`), and nzbget (`/^version-v/`).

When adding a new linuxserver image, check if its version tags conflict with ubuntu date tags and add an `allowedVersions` entry if needed.

### Flake input updates (GitHub Actions)

`.github/workflows/update-flake-inputs.yml` runs `nix flake update` daily (00:00 Europe/Stockholm) and on manual dispatch. It does not commit to `main` directly:

1. Diffs `flake.lock` before/after; skips the rest if nothing changed.
2. Snapshots `nixosConfigurations.ligma.config.environment.systemPackages` (name + version, via `parseDrvName`) before and after the update. ligma's package set is representative — `common/default.nix`'s explicit `systemPackages` list is identical across all three hosts, and the module-pulled packages (postgresql, grafana, podman, etc.) mirror the shared `common/` modules. Eval failure degrades gracefully (`nix eval` wrapped in `||`) rather than failing the run — same pattern as the makizen flake-lock workflow (`makizen/.forgejo/workflows/update-flake-lock.yml`), which does the same snapshot/diff against `home.packages`.
3. Runs `nix flake check` against the updated lock and records pass/fail.
4. Builds a PR body table of the flake's direct inputs (`nixpkgs`, `disko`, `impermanence`, `sops-nix`) that changed rev, with before/after dates and a GitHub compare link per input. Transitive inputs (e.g. `home-manager`, pulled in by `impermanence`) are excluded from the table. A second table lists packages whose version changed between the before/after snapshots.
5. Opens (or updates, if one is already open) a PR on branch `update/flake-lock` via `peter-evans/create-pull-request`, titled with the check result. **`nix flake check` failures do not block the PR** — it's still opened, flagged with ⚠️, so the update is visible either way.
6. Prepends the same flake-input/package diff to `CHANGELOG.md` at the repo root, under a `## <date>` heading, so the history survives after the PR merges (the PR body itself vanishes once the PR is closed). Same mechanism as `makizen/.forgejo/workflows/update-flake-lock.yml` — reuses the exact rows already computed for the PR body, just with `###` sub-headings instead of `##`. The PR includes `CHANGELOG.md` alongside `flake.lock` (`add-paths`).

Requires repo setting **Settings → Actions → General → Workflow permissions → "Allow GitHub Actions to create and approve pull requests"** enabled, or `peter-evans/create-pull-request` fails to open the PR with the default `GITHUB_TOKEN`.
