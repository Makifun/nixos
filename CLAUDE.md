# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based system configuration for three hosts:

- **ligma** — production services host on Proxmox; ephemeral root (tmpfs), LUKS+ZFS, SOPS, impermanence.
- **bofa** (VM 888, 10.10.10.14) — dedicated database host on Proxmox; ephemeral root (tmpfs), LUKS+XFS+LVM. Runs TimescaleDB for tracearr + all arr apps.
- **storma** (10.10.10.12) — physical ASUS K56CB; ephemeral root (tmpfs), LUKS+LVM, systemd-boot (UEFI, `canTouchEfiVariables=false`). Previously hosted rclone `/cloud` mount; role transferred to playma. `r8169` in initrd for LUKS unlock SSH.
- **playma** (10.10.10.15) — NixOS VM on Proxmox; Plex + `/cloud` mounted via CIFS from storma, re-exported via Samba to sugma (port 445, guest auth). Intel GVT-g iGPU for hardware transcoding.

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

### Ephemeral Root + Impermanence

Root `/` is a tmpfs (wiped on reboot). Persistent state lives in `/persist` (ZFS dataset on `zroot`). SSH host keys, systemd state, logs, and podman storage are explicitly persisted via the impermanence module. Any new service needing persistent state must declare it explicitly.

### Disk Layout — ligma (`hosts/ligma/disko-config.nix`)

Three encrypted drives:

- **Main drive** (`scsi-0QEMU_QEMU_HARDDISK_nixos`): LUKS → ZFS pool `zroot` with datasets `/nix` and `/persist` (refreservation: 10G), plus 1G EFI partition.
- **Storage drive** (`scsi-0QEMU_QEMU_HARDDISK_ligma`): LUKS → ZFS pool `zstorage` with `/ligma` dataset (refreservation: 5G). All app persistent data lives here.
- **Cache SSD** (`scsi-0QEMU_QEMU_HARDDISK_cache`, 200 GB): LUKS → ext4 mounted at `/rclone-cache`. Used as rclone VFS cache (up to 185 GB).
Both drives use XFS with `noatime,nofail`. LUKS passphrases entered via initrd SSH at boot. **New VM install:** disko formats on `nixos_install.sh`. **Existing VM adding a disk:** must manually partition + luksFormat + mkfs.xfs before `nh os switch` — see comments in `disko-config.nix`.

All ZFS pools: ashift=12, autotrim=on, compression=lz4, atime=off, xattr=sa. ARC max=6 GB, min=2 GB (ligma has 16 GB RAM). Prefetch disabled (`zfs_prefetch_disable=1`).

### Disk Layout — bofa (`hosts/bofa/disko-config.nix`)

Two encrypted drives (no ZFS — lower overhead for DB workloads):

- **OS disk** (50 G, `scsi-0QEMU_QEMU_HARDDISK_nixos`): 1 G EFI + LUKS(`crypted_nixos`) → LVM `vg_nixos` → XFS `/nix` (25 G) + XFS `/persist` (~24 G). Single passphrase for both via LVM.
- **Data disk** (100 G, `scsi-0QEMU_QEMU_HARDDISK_bofa`): LUKS(`crypted_bofa`) → XFS `/bofa`. All app data lives here (postgresql, backrest, beszel).

XFS mount options: `noatime,discard`.

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
| `monitoring.nix` | Prometheus + Grafana | 9090, 9100, 3000 | 30d retention. Grafana OIDC via Authentik, role from `groups` claim. Alerting: Authentik login success/failure → Gotify webhook. Dashboards (from `grafana_dashboards/`): rclone, registry, rclone-transfers, podman-containers, node-exporter-full, opnsense, proxmox. Scrape jobs: rclone, prometheus, distribution (debug ports 5011-5014), loki, alloy, opnsense-node, opnsense, pve (relay: `?target=proxmoxifun.makifun.se` → `127.0.0.1:9221/pve`). SOPS: `grafana-secret-key`, `grafana-oauth-secret`, `grafana-gotify-token`. |
| `pve-exporter.nix` | prometheus-pve-exporter | 9221 | Proxmox API metrics for Grafana proxmox dashboard. Config written to `/run/pve-exporter.yml` by `pve-exporter-config.service` (oneshot, `chmod 444` — container runs non-root). `verify_ssl: true` (Proxmox has LE cert). SOPS: `proxmox-pve-token-value`. One-time Proxmox setup: create user `prometheus@pve` + API token `prometheus` with PVEAuditor role; **apply the role to both user and token** (privilege separation = intersection — token role alone is not enough). `pveum aclmod / --users 'prometheus@pve' --roles PVEAuditor --propagate 1`. |
| `backrest.nix` | Backrest backup manager | 9898 | Restic-backed S3. Backs up `/ligma/ligma` (`:ro`). `/ligma/restore` mounted rw for restore staging. Schedule: 04:00 UTC. Prune: 05:00 UTC. SOPS: `backrest-restic-password`, `backrest-repo-uri`, `backrest-aws-access-key-id`, `backrest-aws-secret-access-key`, `backrest-gotify-token`. |
| `rclone.nix` | rclone S3 FUSE mount | 6969 (RC), 6970 (metrics) | Shared module used by ligma, storma, and playma. Mounts S3 crypt remote at `/cloud`. VFS cache at `/rclone-cache`. **Primary cloud host is now playma (10.10.10.15).** |
| `samba.nix` | Samba/CIFS share | 445 | Exposes `/cloud` as `\\<host>\cloud`. Guest access, force user=root. `hosts allow`: jonny (10.10.10.16) + sugma nodes (10.10.10.26-28). Sugma cloud PVs point to playma (10.10.10.15). |
| `omni.nix` | Sidero Omni (Talos cluster manager) | 9999 (UI), 50180/udp (WG), 8091 (machine API), 8098/6443 (k8s proxy) | Distroless container. SAML auth via Authentik. JWT key is OpenPGP ASCII-armor (not PEM). SOPS: `omni-account-uuid`, `omni-jwt-signing-key`. |
| `gotify.nix` | Gotify push notifications | 8096 | v3 native OIDC via Authentik (`auth.makifun.se/application/o/gotify/`). Two-router split: `X-Gotify-Key` header bypass (push senders), catch-all no-middleware (Gotify handles OIDC itself). Client secret from SOPS `gotify-oidc-secret` → `/run/gotify-oidc.env` via `gotify-env-setup` oneshot. `GOTIFY_OIDC_LINK_BY_USERNAME=true` links existing local users. |
| `apprise.nix` | Apprise notification aggregator | 8097 | Three-router split: `/outpost` callback, `/notify` path (API bypass for senders), catch-all SSO. |
| `beszel.nix` | Beszel monitoring hub + agent | 8095 (hub), 45876 (agent) | Hub loopback. Agent runs host networking (must see host interfaces). Agent KEY from SOPS `beszel_agent_key`. Hub connects OUT to agents. |
| `distribution.nix` | OCI registry mirrors | 5001-5004 | Four instances: dockerhub (5001), ghcr (5002), lscr (5003), quay (5004). Daily GC at 06:00 UTC. LAN-only via `mirror-lan-only` ipAllowList middleware. `log.level = "info"` — HTTP request logs visible in Loki (`job=ligma-podman-dist-*`). Client IPs are NOT visible here (containers see Podman bridge `10.88.0.1`); use Traefik JSON access logs for real client IPs (`RouterName =~ "dist-.+"`). |
| `unifi.nix` | UniFi Network Application | 8443 (UI), 8080 (inform), 3478/udp (STUN), 10001/udp (discovery), 5141/udp (syslog in) | Two Podman containers (`unifi_network`): MongoDB 8 + linuxserver/unifi. Syslog on 5141 ingested by Alloy → Loki (job=ligma-unifi). UI self-signed cert — Traefik uses `insecureSkipVerify`. PUID/PGID=1000, MEM_LIMIT=1024M. |
| `watchyourlan.nix` | WatchYourLAN network presence monitor | 8840 (UI) | Lightweight ARP scanner; notifies via Shoutrrr → Gotify on new/returning devices. Host networking + NET_ADMIN/NET_RAW caps required. Config written on first boot from SOPS `watchyourlan-gotify-token`; UI changes persist (delete `config_v2.yaml` to reset). Scans `ens18` every 60s. SOPS: `watchyourlan-gotify-token`. |
| `garage.nix` | Garage S3-compatible object store | 3900 (S3 API) | Single-node (`replication_factor=1`). Data at `/ligma/garage/{data,meta}`. Admin API loopback-only (3901). RPC loopback-only (3902). No Traefik — clients connect to `http://10.10.10.13:3900` directly. Port 3900 open to LAN+WG. SOPS: `garage-rpc-secret` (`openssl rand -hex 32`), `garage-admin-token`. **Bootstrap (run once after first deploy):** `podman exec garage /garage layout assign -z dc1 -c 280G <node-id> && podman exec garage /garage layout apply --version 1`. Create buckets/keys with `podman exec garage /garage bucket create <name>` and `podman exec garage /garage key create <name>`. |
| `hosts/ligma/dns-records.nix` | DNS record module | — | Defines `ligma.dnsRecords` option. Each app sets `ligma.dnsRecords."<fqdn>".value = "<ip>"` and a `systemd.services.dns-record-<name>` oneshot runs `nsupdate` with TSIG to register the record in Technitium at `10.10.10.3`. SOPS: `technitium-tsig-key` (base64 HMAC-SHA256 secret, key name `ligma-key`). Services retry on failure until Technitium is reachable. |
| `common/autoupgrade-notify.nix` | Gotify notifier on `nixos-upgrade` | — | `OnSuccess`/`OnFailure` hooks; title uses hostname; includes generation + NixOS version; failure attaches last 40 journal lines (capped 3500 bytes). SOPS: `nixos-upgrade-gotify-token`. |
| `renovate.nix` | Renovate dependency updater | — | Hourly Podman one-shot (systemd timer, 5m random delay). Token from `/ligma/ligma/renovate/token`. SOPS: `renovate-github-token` (GITHUB_COM_TOKEN, for release notes). To regenerate token: `rm /ligma/ligma/renovate/token && systemctl restart forgejo-provision`. |
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
| `beszel.nix` | Beszel agent | 45876 | Monitors bofa; reports disk usage of `/bofa` and `/persist`. Port 45876 open to ligma only. |
| `pg-dump.nix` | PostgreSQL logical dump | — | `pg_dump -Fc` (zlib-compressed custom format) via `podman exec timescaledb`. Dumps to `/bofa/dumps/tracearr_<stamp>.dump`. Daily at 03:00 UTC (±15 min). 30-day on-disk retention. Password from SOPS `timescaledb-tracearr-password`. |

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

Beszel hub (loopback port 8095) + agent (host networking, port 45876). Agent must run on host networking to see host interfaces. Hub connects OUT to agents — open firewall port 45876 to LAN.

**Bootstrap sequence** (one-time, agent KEY not known until hub first runs):
1. Deploy config (hub starts, agent fails without KEY — expected)
2. Open https://beszel.makifun.se → create admin account
3. Add system "ligma", host `10.88.0.1` (Podman gateway), port 45876
4. Copy KEY value → `sops hosts/ligma/secrets.yaml` as `beszel_agent_key`
5. `nh os switch` → agent picks up key and connects

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

### Renovate (GitHub web app)

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
