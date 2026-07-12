# ARR Stack + Jellyfin

> Radarr (HD+4K) · Sonarr (HD+4K) · Lidarr · Prowlarr · Bazarr
> qBittorrent (via AirVPN WireGuard VPN) · Gluetun · Recyclarr · FlareSolverr
> Jellyfin · Jellyseerr · Jellystat
> Part of the Eirdom infrastructure

---

## Overview

The complete Eirdom media stack — automated acquisition through the
ARR suite, streaming through Jellyfin, requests through Jellyseerr,
and analytics through Jellystat.

**The goal:** a private Netflix experience backed by AD authentication
so every family member logs in with their domain credentials.

---

## Architecture

```text
FlareSolverr ──► Prowlarr ──► Radarr HD    ──► Gluetun (VPN) ──► /data/radarr/
                          ├──► Radarr 4K    ──►  qBittorrent   ──► /data/radarr-4k/
                          ├──► Sonarr HD    ──►  (inside VPN)  ──► /data/sonarr/
                          ├──► Sonarr 4K    ──►                ──► /data/sonarr-4k/
                          └──► Lidarr       ──►                ──► /data/lidarr/
                                    │
                               Recyclarr (quality profiles)
                                    │
                         Bazarr (subtitles for all libraries)

/data/radarr/ ────────────────────────────────────────────────► Jellyfin
/data/radarr-4k/ ─────────────────────────────────────────────► Jellyfin
/data/sonarr/ ─────────────────────────────────────────────────► Jellyfin
/data/sonarr-4k/ ──────────────────────────────────────────────► Jellyfin
/data/lidarr/ ─────────────────────────────────────────────────► Jellyfin
                                                                      │
                                                               Jellyseerr (requests)
                                                               Jellystat (analytics)
```

---

## VPN Architecture

qBittorrent routes ALL traffic through an AirVPN WireGuard VPN tunnel
managed by Gluetun. All other ARR services (Radarr, Sonarr, Prowlarr
etc.) connect to the internet normally — they only make lightweight
HTTPS metadata requests to indexers, not torrent data transfers.

```
qBittorrent
  └── network_mode: service:gluetun
        └── Gluetun (WireGuard tunnel)
              └── AirVPN VPN Server
```

**Key points:**

- qBittorrent has no independent network interface — it shares
  Gluetun's network namespace entirely
- Kill switch is enforced by Gluetun — if the VPN tunnel drops,
  qBittorrent loses all network access immediately
- Traefik labels are on the **Gluetun container**, not qBittorrent
- ARR apps reach qBittorrent at `http://gluetun:8080` — never
  `http://qbittorrent:8080` (that hostname has no network)
- Port forwarding uses an AirVPN **reserved port**, passed via
  `VPN_FORWARDED_PORT`. The port is account-bound and persists
  across servers and reconnects — set qBittorrent's listening
  port to the same value
- Server selection is by country (`VPN_SERVER_COUNTRIES`), not a
  hardcoded endpoint — Gluetun ships AirVPN's server keys

**Why AirVPN (ADR-042):** Italian jurisdiction (outside the US legal
pressure that made TorGuard block BitTorrent on its own US servers),
and a static reserved port that survives reconnects — the lowest-
fragility option for a 24/7 unattended seeder.

---

## Server Hardware Notes

**EIRDOM-DOCKER-01 — Intel Xeon X3430 (2009)**

This CPU has no Quick Sync and no VAAPI support. There is no hardware
transcoding available on this server.

**Jellyfin is configured for direct play only.** This means:

- Clients must be capable of playing the file natively
- 4K HDR/Dolby Vision requires a capable client (Apple TV 4K,
  Fire TV Stick 4K, Shield TV, or any browser/app with HEVC support)
- If a client requests a format it cannot play natively, Jellyfin
  will attempt CPU transcoding — this will be slow on a 4-core
  2.4GHz Xeon and may not keep up with 4K content
- Recommended: configure each client's Jellyfin app to set max
  streaming bitrate to "Original" and enable Direct Play

If you upgrade to a server with an Intel 12th gen or newer iGPU,
hardware transcoding (Quick Sync + HDR tone mapping) can be enabled
by uncommenting the `devices:` section in the Jellyfin compose file.

---

## Storage Layout

Three physical tiers, split by access pattern (ADR-043). Completed
downloads and libraries share one filesystem (Tier 3), so hardlinks
still work; the write-heavy workloads (configs, active downloads) are
moved onto SSDs.

| Tier | Contents | Host path | Container path |
|------|----------|-----------|----------------|
| 1 | Service configs (SQLite) | `${DOCKER_DATA_PATH}` (OS/Docker SSD) | `/config` |
| 2 | In-progress downloads | `${DOWNLOADS_CACHE_PATH}` (250GB SSD) | `/incomplete` |
| 3 | Completed downloads + libraries | `${MEDIA_PATH}` = `/media/arr` (3TB WD Red) | `/data` |

```
Tier 3 — /media/arr  (3TB WD Red, sda1, ext4)  →  /data in containers
├── downloads/
│   └── complete/                qBittorrent finished (seeds from here)
│       ├── radarr/              Radarr HD imports from here
│       ├── radarr-4k/           Radarr 4K imports from here
│       ├── sonarr/              Sonarr HD imports from here
│       ├── sonarr-4k/           Sonarr 4K imports from here
│       ├── lidarr/              Lidarr imports from here
│       └── manual/
├── radarr/                      HD movie library (EXISTING — 449GB)
├── radarr-4k/                   4K movie library (EXISTING — 246GB)
├── sonarr/                      HD TV library    (EXISTING — 795GB)
├── sonarr-4k/                   4K TV library    (EXISTING —  71GB)
└── lidarr/                      Music library    (EXISTING — 1.3GB)

Tier 2 — 250GB SSD  →  /incomplete in qBittorrent
   Active downloads only. qBittorrent moves each finished file to
   Tier 3's downloads/complete/, so this drive self-clears — no
   cleanup script needed.

Tier 1 — OS/Docker SSD  →  /config in every service
   gluetun/ radarr/ radarr-4k/ sonarr/ sonarr-4k/ lidarr/
   prowlarr/ bazarr/ qbittorrent/ recyclarr/ jellyfin/
   jellyseerr/ jellystat/
```

> **Hardlinks still work** because the only hardlinked pair —
> `downloads/complete/` and the library folders (`radarr/`, `sonarr/`
> etc.) — both live on Tier 3 (`/media/arr` → `/data`). The
> incomplete → complete transition (Tier 2 SSD → Tier 3 HDD) is a
> one-time cross-filesystem copy, by design.

> **`DOCKER_DATA_PATH` is shared (root `.env`).** Repointing it to the
> OS SSD moves **every** stack's config dirs off `/media/arr`, not just
> the ARR stack — this is intentional (configs/DBs belong on fast
> storage), but do it as a single coordinated migration (see below).

> **Existing media is untouched.** `/media/arr` *is* the 3TB WD Red, so
> the library folders do not move. Do not rename `radarr/`, `sonarr/`
> etc. — point each ARR app's root folder to the existing path.

---

## Pre-Deployment Setup

### Step 1 — Mount drives and create the tier directories

> This guide uses `/opt/eirdom/appdata` as the Tier-1 (OS SSD) config
> base — i.e. the new value of `DOCKER_DATA_PATH` — and
> `/mnt/downloads-cache` as the Tier-2 (250GB SSD) mount. Adjust to your
> actual mount points and set them in the root `.env` and arr-stack
> `.env`.

```bash
# --- Mount the SSDs (get UUIDs with: sudo blkid), add to /etc/fstab ---
#   UUID=<250GB-ssd>  /mnt/downloads-cache  ext4  defaults,noatime  0 2
# (Tier 3, /media/arr = the 3TB WD Red, is already mounted.)

# Tier 1 config base (OS SSD) + Tier 2 download cache (250GB SSD)
sudo mkdir -p /opt/eirdom/appdata /mnt/downloads-cache

# Tier 3 — completed download category folders (on the existing 3TB)
sudo mkdir -p /media/arr/downloads/complete/{radarr,radarr-4k,sonarr,sonarr-4k,lidarr,manual}

# Tier 1 — per-service config dirs on the OS SSD
sudo mkdir -p /opt/eirdom/appdata/{gluetun,radarr,radarr-4k,sonarr,sonarr-4k,lidarr}
sudo mkdir -p /opt/eirdom/appdata/{prowlarr,bazarr,qbittorrent,recyclarr}
sudo mkdir -p /opt/eirdom/appdata/{jellyfin,jellyseerr,jellystat/db,jellystat/backup-data}

# Ownership
sudo chown -R 1000:1000 /opt/eirdom/appdata /mnt/downloads-cache /media/arr/downloads
```

**Migrating an existing deployment?** Configs are moving off
`/media/arr/config`. Do it once, with the stack stopped:

```bash
cd docker/arr-stack && docker compose down      # and any other stacks
# Move every stack's configs from the 3TB to the OS SSD:
sudo rsync -aHAX --info=progress2 /media/arr/config/ /opt/eirdom/appdata/
# Then set DOCKER_DATA_PATH=/opt/eirdom/appdata in the root .env.
# Once confirmed working, the old /media/arr/config can be removed.
# The old /media/arr/downloads/incomplete is now unused (incomplete
# lives on the 250GB SSD) and can also be removed.
```

### Step 2 — Get AirVPN WireGuard credentials

1. Log into the AirVPN Client Area at `airvpn.org`
2. Go to **Config Generator**, select **WireGuard**, pick a device,
   and choose a server **country** geographically close to you
3. Generate and open the config
4. Extract the following values into `docker/arr-stack/.env`:

```ini
# From the [Interface] section:
PrivateKey   = → WIREGUARD_PRIVATE_KEY
PresharedKey = → WIREGUARD_PRESHARED_KEY     # AirVPN-specific
Address      = → WIREGUARD_ADDRESSES
```

5. Set the server filter — no endpoint IP needed, Gluetun ships
   AirVPN's server keys:

```ini
VPN_SERVER_COUNTRIES=Canada
```

6. Reserve a forwarded port in **Client Area → Ports** (any port
   ≥ 2048), then set it as `VPN_FORWARDED_PORT`. It is account-bound
   and persists across servers and reconnects. Use the same value as
   qBittorrent's listening port.

### Step 3 — Create AD service account and groups for Jellyfin

On EIRDOM-DC-01:

1. Create service account:
   `CN=jellyfin-svc,OU=Service Accounts,OU=Eirdom,DC=ad,DC=eirdom,DC=homes`
   — Password never expires, no login rights

2. Create security groups in
   `OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes`:

| Group | Purpose |
|-------|---------|
| `Jellyfin-Users` | Standard streaming access |
| `Jellyfin-Admins` | Full Jellyfin admin access |

3. Add family members to `Jellyfin-Users`. Add your admin account
   to both groups.

### Step 4 — Fill in .env files

```bash
# ARR stack
cd docker/arr-stack
cp .env.example .env
nano .env
# Fill in all WireGuard values from Step 2

# Jellyfin stack
cd docker/jellyfin
cp .env.example .env
nano .env
# Generate JELLYSTAT_DB_PASSWORD: openssl rand -base64 32
# Generate JELLYSTAT_JWT_SECRET:  openssl rand -base64 32
```

---

## Deployment Order

### 1. Start ARR stack

```bash
cd docker/arr-stack
docker compose up -d
docker compose logs -f
```

Watch for Gluetun to connect before other services start:

```
gluetun | Connected to AirVPN WireGuard
```

All ARR services depend on `gluetun: condition: service_healthy`
and will wait until the VPN tunnel is established.

### 2. Start Jellyfin stack

```bash
cd docker/jellyfin
docker compose up -d
docker compose logs -f
```

---

## Post-Deployment Configuration

### Gluetun / VPN — Verify tunnel is working

```bash
# Check Gluetun logs
docker logs gluetun --tail 30

# Verify qBittorrent is using the VPN IP (not your home IP)
docker exec -it qbittorrent curl -s https://ipinfo.io
# Should return an AirVPN server IP — NOT your home IP
```

---

### qBittorrent

1. Get temporary password:
   ```bash
   docker logs qbittorrent 2>&1 | grep -i "password"
   ```

2. Login at `https://qbit.eirdom.homes`

3. **Settings → Downloads:**

   | Setting | Value |
   |---------|-------|
   | Default Save Path | `/data/downloads/complete` (Tier 3, 3TB) |
   | Keep incomplete torrents in | `/incomplete` (Tier 2, 250GB SSD) |

   > On completion qBittorrent moves the file from `/incomplete` (SSD)
   > to `/data/downloads/complete` (3TB). That cross-filesystem move is
   > what keeps the SSD cache clear — no cleanup job needed.

4. **Add categories** (right-click category panel → Add):

   | Category | Save Path |
   |----------|-----------|
   | `radarr` | `/data/downloads/complete/radarr` |
   | `radarr-4k` | `/data/downloads/complete/radarr-4k` |
   | `sonarr` | `/data/downloads/complete/sonarr` |
   | `sonarr-4k` | `/data/downloads/complete/sonarr-4k` |
   | `lidarr` | `/data/downloads/complete/lidarr` |
   | `manual` | `/data/downloads/complete/manual` |

5. **Settings → BitTorrent — CRITICAL:**

   | Setting | Value |
   |---------|-------|
   | When ratio reaches | your seed goal (see note) |
   | …or total seeding time reaches | your seed goal (see note) |
   | then | `Remove torrent and its files` |

   > "Remove torrent and its files" is the key setting. The hardlink
   > in your media library survives this deletion — only the download
   > copy is removed. Without this your drive fills up.
   >
   > **Private trackers:** do NOT remove at ratio 1.0 blindly. Set the
   > ratio/seed-time to your strictest tracker's required minimum, or
   > you risk hit-and-run bans. For public-only use, ratio `1.0` is fine.

6. **Settings → Connection — Port forwarding:**

   | Setting | Value |
   |---------|-------|
   | Listening Port | value of `VPN_FORWARDED_PORT` (the AirVPN reserved port) |
   | Use UPnP / NAT-PMP | Disabled |

7. **Settings → Web UI:**

   | Setting | Value |
   |---------|-------|
   | Trusted reverse proxies | `gluetun` |
   | Enable CSRF protection | Enabled |

---

### Prowlarr

1. Add FlareSolverr: Settings → Indexers → FlareSolverr
   - URL: `http://flaresolverr:8191`

2. Add indexers

3. Connect apps: Settings → Apps → Add Application:

   | App | URL | Category |
   |-----|-----|----------|
   | Radarr | `http://radarr:7878` | `radarr` |
   | Radarr 4K | `http://radarr-4k:7878` | `radarr-4k` |
   | Sonarr | `http://sonarr:8989` | `sonarr` |
   | Sonarr 4K | `http://sonarr-4k:8989` | `sonarr-4k` |
   | Lidarr | `http://lidarr:8686` | `lidarr` |

   Use **Full Sync** for each.

---

### Radarr HD

- Settings → Download Clients → Add → qBittorrent
  - Host: `gluetun` ← NOT `qbittorrent`
  - Port: `8080`
  - Category: `radarr`
- Settings → Media Management → Add Root Folder: `/data/radarr`
- Settings → Media Management → Import using Hardlinks: **Enabled**

### Radarr 4K

- Download client host: `gluetun`, Port: `8080`
- Category: `radarr-4k`
- Root Folder: `/data/radarr-4k`
- Import using Hardlinks: **Enabled**

### Sonarr HD

- Download client host: `gluetun`, Port: `8080`
- Category: `sonarr`
- Root Folder: `/data/sonarr`
- Import using Hardlinks: **Enabled**

### Sonarr 4K

- Download client host: `gluetun`, Port: `8080`
- Category: `sonarr-4k`
- Root Folder: `/data/sonarr-4k`
- Import using Hardlinks: **Enabled**

### Lidarr

- Download client host: `gluetun`, Port: `8080`
- Category: `lidarr`
- Root Folder: `/data/lidarr`
- Import using Hardlinks: **Enabled**

### Bazarr

Connect to all four Radarr/Sonarr instances:

Settings → Radarr → Add:
- `http://radarr:7878` — API key from `RADARR_API_KEY`
- `http://radarr-4k:7878` — API key from `RADARR_4K_API_KEY`

Settings → Sonarr → Add:
- `http://sonarr:8989` — API key from `SONARR_API_KEY`
- `http://sonarr-4k:8989` — API key from `SONARR_4K_API_KEY`

---

### Recyclarr

1. Copy the recyclarr.yml from the repo to the config directory
   (Tier 1 — `$DOCKER_DATA_PATH`, the OS SSD):
   ```bash
   cp docker/arr-stack/recyclarr.yml /opt/eirdom/appdata/recyclarr/recyclarr.yml
   ```

2. Create the secrets file:
   ```bash
   cat > /opt/eirdom/appdata/recyclarr/secrets.yml <<EOF
   radarr_api_key: YOUR_RADARR_API_KEY
   radarr_4k_api_key: YOUR_RADARR_4K_API_KEY
   sonarr_api_key: YOUR_SONARR_API_KEY
   sonarr_4k_api_key: YOUR_SONARR_4K_API_KEY
   EOF
   chmod 600 /opt/eirdom/appdata/recyclarr/secrets.yml
   ```

3. Run a manual sync to create the quality profiles:
   ```bash
   docker exec recyclarr recyclarr sync
   ```

4. Verify in Radarr HD → Settings → Quality Profiles that `HD-1080p`
   was created. In Radarr 4K verify `4K-2160p` was created.

---

### Jellyfin

#### 1. Initial setup

Navigate to `https://jellyfin.eirdom.homes` and complete the setup
wizard. Create an initial local admin account — you can disable it
after LDAP is working.

Add libraries pointing to existing media:

| Library | Type | Path |
|---------|------|------|
| Movies | Movies | `/data/radarr` |
| Movies 4K | Movies | `/data/radarr-4k` |
| TV Shows | Shows | `/data/sonarr` |
| TV Shows 4K | Shows | `/data/sonarr-4k` |
| Music | Music | `/data/lidarr` |

#### 2. Configure direct play (disable transcoding)

Dashboard → Playback → Transcoding:

| Setting | Value |
|---------|-------|
| Hardware acceleration | None |
| Allow encoding | Disabled |

> This forces clients to direct play. All modern streaming devices
> (Apple TV 4K, Fire TV 4K, Shield TV) support HEVC/H.265 direct
> play for 4K content.

#### 3. Install and configure LDAP plugin

Dashboard → Plugins → Catalog → search "LDAP Authentication" →
Install → restart Jellyfin.

After restart, Dashboard → Plugins → LDAP Authentication:

| Field | Value |
|-------|-------|
| LDAP Server | `10.1.10.10` |
| LDAP Port | `389` |
| Secure LDAP | Disabled (use STARTTLS) |
| StartTLS | Enabled |
| Base DN | `DC=ad,DC=eirdom,DC=homes` |
| Bind User | `CN=jellyfin-svc,OU=Service Accounts,OU=Eirdom,DC=ad,DC=eirdom,DC=homes` |
| Bind Password | from `.env` `JELLYFIN_LDAP_BIND_PASSWORD` |
| LDAP Search Filter | `(&(objectClass=user)(memberOf=CN=Jellyfin-Users,OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes))` |
| LDAP Search Attributes | `sAMAccountName, mail, displayName` |
| Admin Base DN | `CN=Jellyfin-Admins,OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes` |
| Enable User Creation | Enabled |

Save and test. AD users in `Jellyfin-Users` should now be able to
log in with their domain credentials.

---

### Jellyseerr

Navigate to `https://requests.eirdom.homes` and complete setup:

1. Sign In → Use your Jellyfin account
   - Jellyfin URL: `http://jellyfin:8096`
   - Enter your Jellyfin admin credentials

2. Connect Radarr instances:
   - Radarr (HD): `http://radarr:7878`, quality profile `HD-1080p`
   - Radarr 4K: `http://radarr-4k:7878`, quality profile `4K-2160p`

3. Connect Sonarr instances:
   - Sonarr (HD): `http://sonarr:8989`, quality profile `HD-1080p`
   - Sonarr 4K: `http://sonarr-4k:8989`, quality profile `4K-2160p`

4. Sync Jellyfin users: Settings → Jellyfin → Import Users —
   all Jellyfin users (from AD) are imported automatically.

---

### Jellystat

1. Navigate to `https://jellystat.eirdom.homes`

2. Create a local admin account on first login

3. Settings → Jellyfin:
   - Server URL: `http://jellyfin:8096`
   - API Key: generate in Jellyfin Dashboard → API Keys → Add
   - Save the key in `.env` as `JELLYFIN_API_KEY`

4. Run an initial sync — Jellystat pulls all watch history from
   Jellyfin and begins tracking statistics.

---

## Verifying Hardlinks

After the first successful import:

```bash
# Check link count — should be 2 while seeding, 1 after torrent removed
stat /media/arr/radarr/Some\ Movie\ \(2024\)/Some.Movie.mkv | grep Links
```

If always 1, hardlinks are not working. Check:
- Radarr → Settings → Media Management → Import using Hardlinks: ON
- Both paths are on `/media/arr` (same filesystem)

---

## Troubleshooting

### VPN not connecting

```bash
docker logs gluetun --tail 50

# Common causes:
# - Incorrect WIREGUARD_PRIVATE_KEY or WIREGUARD_PRESHARED_KEY
# - VPN_SERVER_COUNTRIES has no matching server / typo
# - AirVPN account not active, or no device slots left on the plan
# Regenerate the config from the AirVPN Client Area and update .env
```

### qBittorrent inaccessible after VPN drop

This is the kill switch working correctly. Check Gluetun status:

```bash
docker logs gluetun --tail 20
docker restart gluetun
# qBittorrent reconnects automatically once VPN is restored
```

### ARR apps cannot reach qBittorrent

Make sure the download client host is set to `gluetun` not
`qbittorrent` in all ARR app settings.

```bash
# Test connectivity from inside Radarr container
docker exec radarr curl -s http://gluetun:8080
# Should return the qBittorrent Web UI HTML
```

---

## Service URLs

| Service | URL | Auth |
|---------|-----|------|
| qBittorrent | `https://qbit.eirdom.homes` | Authentik + qBit login |
| Prowlarr | `https://prowlarr.eirdom.homes` | Authentik SSO |
| Radarr | `https://radarr.eirdom.homes` | Authentik SSO |
| Radarr 4K | `https://radarr4k.eirdom.homes` | Authentik SSO |
| Sonarr | `https://sonarr.eirdom.homes` | Authentik SSO |
| Sonarr 4K | `https://sonarr4k.eirdom.homes` | Authentik SSO |
| Lidarr | `https://lidarr.eirdom.homes` | Authentik SSO |
| Bazarr | `https://bazarr.eirdom.homes` | Authentik SSO |
| Jellyfin | `https://jellyfin.eirdom.homes` | AD LDAP |
| Jellyseerr | `https://requests.eirdom.homes` | Jellyfin account |
| Jellystat | `https://jellystat.eirdom.homes` | Authentik + local |

---

## DNS Records

Add to internal DNS on EIRDOM-DC-01 (all point to 10.1.50.10):

```
radarr4k.eirdom.homes     A    10.1.50.10
sonarr4k.eirdom.homes     A    10.1.50.10
requests.eirdom.homes     A    10.1.50.10
jellystat.eirdom.homes    A    10.1.50.10
```

> `radarr.eirdom.homes`, `sonarr.eirdom.homes`, `jellyfin.eirdom.homes`
> etc. should already exist from the previous deployment.

---

## Related Documentation

- [`services.md`](../../docs/services.md) — Master service reference
- [`lan-rules.md`](../../unifi/firewall/lan-rules.md) — Firewall rules
- [`decisions.md`](../../docs/decisions.md) — Architecture decisions