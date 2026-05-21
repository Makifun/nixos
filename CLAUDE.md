# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

NixOS flake-based system configuration for a single production host (`ligma`) running on Proxmox. Key features: ephemeral root (tmpfs), full disk encryption (LUKS+ZFS), SOPS secrets, and impermanence.

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

- **`flake.nix`** — Defines two outputs: `nixosConfigurations.ligma` (production) and `nixosConfigurations.minimaliso` (bootstrap ISO). Inputs: nixpkgs (25.11), disko, impermanence, sops-nix. **Note: authentik-nix was removed** — Authentik now runs as Podman containers.
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

SSH restricted to `10.10.10.0/24`. NFTables firewall. IPv6 disabled globally. Only ports 80, 443, and 2049 (NFS) open externally.

NFS exports (restricted to specific IPs — `hosts/ligma/apps/nfs.nix`):
- `/ligma/sugma` → sugma nodes `10.10.10.26`, `10.10.10.27`, `10.10.10.28` (rw, nfs-provisioner PVC storage)
- `/cloud` → jonny `10.10.10.16` (rw, rclone FUSE mount re-exported; jonny mounts at `/mnt/cloud`)

### Auto-upgrade

`hosts/ligma/default.nix` enables `system.autoUpgrade` pulling from the GitHub flake. Changes pushed to the repo will be automatically applied.

### Services (`hosts/ligma/apps/`)

| File | Service | Notes |
|---|---|---|
| `traefik.nix` | Traefik reverse proxy | Handles TLS termination for all apps |
| `authentik.nix` | Authentik SSO | Three Podman containers (`authentik_network`): Redis + server (port 9000) + worker. Native PostgreSQL at `/ligma/ligma/authentik/postgresql`. `/run/postgresql` bind-mounted with `trust` auth (no password). SOPS secret: `authentik_env`. |
| `forgejo.nix` | Forgejo + Actions runner | Port 3010; SSH on 22222; waits for `podman-authentik-server` + `podman-authentik-worker` on boot |
| `vaultwarden.nix` | Vaultwarden | Password manager |
| `homepage.nix` | Homepage dashboard | Port 8082; nginx on 8083 serves `/images/`; connects to sugma k8s via kubeconfig |
| `graylog.nix` | Graylog 7 log management | Port 9099; three Podman containers on `graylog_network`: MongoDB 8, Graylog-datanode 7, Graylog 7 |
| `monitoring.nix` | Prometheus + Grafana | Prometheus port 9090, 30d retention; node_exporter port 9100 (systemd collector enabled); scrapes rclone RC `/metrics` on port 6969. Grafana port 3000, OIDC via Authentik (`grafana-sso` application), role from `groups` claim (`grafana_admin`→Admin, `app_admins`→Admin, `grafana_viewer`→Viewer). SOPS secrets: `grafana-secret-key`, `grafana-oauth-secret`. Rclone dashboard auto-provisioned from `grafana_dashboards/rclone.json` via `environment.etc` + dashboard provider at `/etc/grafana-dashboards`. |
| `backrest.nix` | Backrest backup manager | Port 9898 loopback; restic-backed; auth disabled, gated by Authentik via Traefik; backs up all of `/ligma` daily |
| `rclone.nix` | rclone S3 FUSE mount | Mounts S3 remote at `/cloud`; RC on port 6969 (`--rc-no-auth`); Prometheus scrapes `/metrics` from this port. Config at `/ligma/ligma/rclone/rclone.conf`. Re-exported via NFS + Samba. |
| `samba.nix` | Samba/CIFS share | Exposes `/cloud` as `\\ligma\cloud`; guest access; `hosts allow` includes sugma nodes (10.10.10.26/27/28) for SMB CSI driver mounts |
| `nfs.nix` | NFS server | Exports `/ligma/sugma` (sugma nodes only) and `/cloud` (jonny only); port 2049 |
| `vector.nix` | Vector log shipper | Ships all systemd journal logs to Graylog GELF UDP (port 12201). `ExecStartPre` waits for port 12201 to be bound before starting (avoids permanent ECONNREFUSED on boot race). |
| `omni.nix` | Sidero Omni (Talos cluster manager) | Container at port 9999 loopback (Traefik fronted); SideroLink WG UDP 50180 on `${ligmaIP}` (LAN-only); SAML auth via Authentik |
| `autoupgrade-notify.nix` | Gotify notifier on `nixos-upgrade` | Templated `OnSuccess`/`OnFailure` units; failure path attaches the last 40 journal lines |
| `renovate.nix` | Renovate dependency updater | Hourly Podman one-shot (systemd timer); `renovate-bot` admin user + API token auto-provisioned by `forgejo-provision` on first boot; token written to `/ligma/ligma/renovate/token` (persists across reboots on zstorage); scopes: `read:misc,read:organization,write:issue,write:repository,read:user,read:package`. To regenerate token (e.g. after scope change): `rm /ligma/ligma/renovate/token && systemctl restart forgejo-provision`. GitHub token for release notes in SOPS as `renovate-github-token`, mounted into container as `GITHUB_COM_TOKEN`. |

### Traefik + Authentik integration

The `authentik` forwardAuth middleware (defined in `traefik.nix`) adds SSO to any router.
The Authentik embedded outpost (port 9000) injects response headers (lowercase, e.g.
`x-authentik-username`) which Traefik copies to the upstream request via `authResponseHeaders`.

Every service protected by the `authentik` middleware also needs a second router for
`PathPrefix(/outpost.goauthentik.io)` pointing to `authentik-embedded-outpost` (no middleware)
so the post-login callback reaches the outpost. See `traefik.nix` for the pattern.

**Graylog uses a three-router priority split** (`graylog.nix`) to support both browser SSO
and Terraform/API token access on the same domain:

| Router | Priority | Rule | Middleware | Purpose |
|--------|----------|------|------------|---------|
| `graylog-outpost` | 30 | `Host + PathPrefix(/outpost.goauthentik.io)` | none | Authentik post-login callback |
| `graylog-basic-auth` | 10 | `Host + HeaderRegexp(Authorization, ^Basic .+)` | none | Terraform API token access (bypasses SSO) |
| `graylog` | 1 | `Host` (catch-all) | `authentik` | Browser SSO — header injected for Trusted Header Auth |

### Journald retention

`hosts/ligma/default.nix` caps journal at **512 MB / 7 days**. Logs ship to Graylog via Vector so unlimited local retention is unnecessary. Vacuum manually: `journalctl --vacuum-size=512M --vacuum-time=7d`.

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

`modules/podman.nix` configures Podman. Container images use the default location (`/var/lib/containers`), which is persisted via impermanence.

### Omni (Sidero Talos cluster manager)

Self-hosted Omni runs as a Podman container on ligma. State (embedded etcd +
SQLite) lives at `/ligma/ligma/omni/`. Auth is delegated to Authentik via SAML
— no Traefik forwardAuth in front of the Omni router. The corresponding
SAML provider, application, and policy binding are defined in the **authentik**
repo at `omni.tf`; that must be `tofu apply`'d before deploying Omni so the
metadata URL `https://auth.makifun.se/application/saml/omni/metadata/` resolves.

Three SOPS secrets live in `hosts/ligma/secrets.yaml`:

| Secret | Purpose | Format |
|---|---|---|
| `omni-account-uuid` | `--account-id` (passed via `OMNI_ACCOUNT_ID` from a sops-rendered env file) | bare UUID string |
| `omni-jwt-signing-key` | `--private-key-source` for embedded-etcd master key encryption | **ASCII-armored OpenPGP private key** (gopenpgp), not raw PEM |
| `omni-wireguard-key` | reserved, currently unused; Omni manages the SideroLink WG private key in its own etcd state | WG private key |

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

Paste the full `-----BEGIN PGP PRIVATE KEY BLOCK-----...END...` into sops as a
YAML literal block (`omni-jwt-signing-key: |`). After editing the secret on a
running ligma, `systemctl restart omni-prep podman-omni` to re-stage and
re-load the key without a full rebuild.

**SAML quirks worth knowing** (configured in the authentik repo, not here):

- Provider `audience` must be `https://omni.makifun.se/saml/metadata` (the
  metadata path), not the bare host. Omni rejects any other value.
- The provider must include the default property mappings (email, name,
  username, uid, upn) and pin `name_id_mapping` to the email mapping —
  Authentik otherwise sends an empty `<saml:AttributeStatement/>` and Omni
  cannot identify the user.
- `--auth-saml-attribute-rules` maps Authentik's MS SOAP claim URIs
  (`http://schemas.xmlsoap.org/ws/2005/05/identity/claims/...`) to Omni's
  internal `identity` and `fullname` fields. Direction is
  `saml-attr → omni-field`.
- `--auth-saml-url` takes the metadata URL despite its name.
  `--auth-saml-metadata` expects a local XML file path, not a URL.

**Other gotchas:**

- Omni's distroless image has no `/bin/sh` — entrypoint must be the binary
  directly, no wrapper script.
- The `--account-id` flag has no env-binding shown in `--help`, but cobra/viper
  auto-binds `OMNI_ACCOUNT_ID`. We use that to keep the UUID out of `/nix/store`.
- Required flags not obvious from `--help`: `--sqlite-storage-path`,
  `--etcd-embedded-db-path`, `--machine-api-advertised-url`. Missing flags fail
  with JSON-schema validation errors that name the missing config path.
- `--initial-users` re-checks on every start and seeds new admin emails.
  Existing users created via the UI are not touched.

### Homepage → Kubernetes integration

`homepage.nix` connects Homepage to the sugma k8s cluster for service discovery and pod metrics.

**How it works:**
- `kubernetes.mode = "default"` + `gateway = true` — enables Gateway API HTTPRoute discovery
- `KUBECONFIG` env var points to a SOPS secret rendered at runtime
- Homepage uses the `homepage` ServiceAccount (scoped read-only ClusterRole) in the `homepage` namespace on sugma

**SOPS secret `homepage-kubeconfig`** — kubeconfig YAML for the sugma cluster. Must be added to
`secrets.yaml` after Flux applies `k8s/infra/homepage-rbac/` on sugma.

**One-time bootstrap** (run after `k8s/infra/homepage-rbac/` is deployed):

```bash
# On a machine with sugma kubeconfig access:
TOKEN=$(kubectl get secret homepage-token -n homepage -o jsonpath='{.data.token}' | base64 -d)
SERVER="https://10.10.10.29:6443"

# On ligma, add to secrets.yaml:
sops hosts/ligma/secrets.yaml
```

Add the following key (use `insecure-skip-tls-verify: true` since the API server uses self-signed cert):

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

`{{HOMEPAGE_VAR_*}}` substitution works in annotations (same pipeline as YAML config).
`pod-selector` must match actual pod labels — homepage defaults to `app.kubernetes.io/name=<name>`
which often doesn't match. Use `gethomepage.dev/pod-selector` to override.

### Auto-upgrade notifications

`apps/autoupgrade-notify.nix` hooks `OnSuccess=`/`OnFailure=` on the
`nixos-upgrade.service` to a templated oneshot (`nixos-upgrade-notify@%i`)
that posts to `https://gotify.makifun.se`. Failure messages include the last
40 journal lines from `nixos-upgrade.service`. The Gotify app token is in
SOPS as `nixos-upgrade-gotify-token`. Test with:

```bash
sudo systemctl start nixos-upgrade-notify@success.service
```
