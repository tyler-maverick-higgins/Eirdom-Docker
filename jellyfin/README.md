# ARR Stack + Jellyfin
> Radarr (HD+4K) · Sonarr (HD+4K) · Lidarr · Prowlarr · Bazarr
> qBittorrent (via TorGuard WireGuard VPN) · Gluetun · Recyclarr · FlareSolverr
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

```
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

qBittorrent routes ALL traffic through a TorGuard WireGuard VPN tunnel
managed by Gluetun. All other ARR services (Radarr, Sonarr, Prowlarr
etc.) connect to the internet normally — they only make lightweight
HTTPS metadata requests to indexers, not torrent data transfers.

```
qBittorrent
  └── network_mode: service:gluetun
        └── Gluetun (WireGuard tunnel)
              └── TorGuard VPN Server
```

**Key points:**

- qBittorrent has no independent network interface — it shares
  Gluetun's network namespace entirely
- Kill switch is enforced by Gluetun — if the VPN tunnel drops,
  qBittorrent loses all network access immediately
- Traefik labels are on the **Gluetun container**, not qBittorrent
- ARR apps reach qBittorrent at `http://gluetun:8080` — never
  `http://qbittorrent:8080` (that hostname has no network)
- Port forwarding is configured via `TORGUARD_FORWARDED_PORT`

**Upgrading to a dedicated IP later:**
Update `VPN_ENDPOINT_IP` in `.env` to your dedicated IP and restart
the stack. No other changes needed.

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

Everything lives on `/media/arr` (sda1, 2.7TB ext4) mounted as
`/data` inside containers. Single filesystem = hardlinks work.

```
/media/arr/                          (/data inside containers)
├── config/                          service config directories
│   ├── gluetun/
│   ├── radarr/
│   ├── radarr-4k/
│   ├── sonarr/
│   ├── sonarr-4k/
│   ├── lidarr/
│   ├── prowlarr/
│   ├── bazarr/
│   ├── qbittorrent/
│   ├── recyclarr/
│   ├── jellyfin/
│   ├── jellyseerr/
│   └── jellystat/
├── downloads/
│   ├── incomplete/                  qBittorrent active downloads
│   └── complete/
│       ├── radarr/                  Radarr HD imports from here
│       ├── radarr-4k/               Radarr 4K imports from here
│       ├── sonarr/                  Sonarr HD imports from here
│       ├── sonarr-4k/               Sonarr 4K imports from here
│       ├── lidarr/                  Lidarr imports from here
│       └── manual/
├── radarr/                          HD movie library (EXISTING — 449GB)
├── radarr-4k/                       4K movie library (EXISTING — 246GB)
├── sonarr/                          HD TV library    (EXISTING — 795GB)
├── sonarr-4k/                       4K TV library    (EXISTING —  71GB)
└── lidarr/                          Music library    (EXISTING — 1.3GB)
```

> **Important:** The existing media folders are preserved exactly as-is.
> Do not move or rename `radarr/`, `sonarr/` etc. After deployment,
> simply point each ARR app's root folder to the existing path.

---

## Pre-Deployment Setup

### Step 1 — Create required directories

```bash
# Download category folders
mkdir -p /media/arr/downloads/incomplete
mkdir -p /media/arr/downloads/complete/{radarr,radarr-4k,sonarr,sonarr-4k,lidarr,manual}

# Config directories (provision.sh handles most but verify)
mkdir -p /media/arr/config/{gluetun,radarr,radarr-4k,sonarr,sonarr-4k,lidarr}
mkdir -p /media/arr/config/{prowlarr,bazarr,qbittorrent,recyclarr}
mkdir -p /media/arr/config/{jellyfin,jellyseerr,jellystat/db,jellystat/backup-data}

# Fix ownership
chown -R 1000:1000 /media/arr/config
chown -R 1000:1000 /media/arr/downloads
```

### Step 2 — Get TorGuard WireGuard credentials

1. Log into the TorGuard client area at `torguard.net`
2. Go to **Tools → WireGuard Config Generator**
3. Select a server location geographically close to you
4. Download the `.conf` file
5. Open it and extract the following values into
   `docker/arr-stack/.env`:

```ini
# From [Interface] section:
PrivateKey = → WIREGUARD_PRIVATE_KEY
Address    = → WIREGUARD_ADDRESSES

# From [Peer] section:
PublicKey  = → WIREGUARD_SERVER_PUBLIC_KEY
Endpoint   = 185.220.101.1:51820
             → VPN_ENDPOINT_IP=185.220.101.1
             → VPN_ENDPOINT_PORT=51820
```

6. Leave `TORGUARD_FORWARDED_PORT` blank until you upgrade to a
   port forwarding-enabled plan

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
gluetun | Connected to TorGuard WireGuard
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
# Should return TorGuard server IP — NOT your home IP
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
   | Default Save Path | `/data/downloads/complete` |
   | Keep incomplete in | `/data/downloads/incomplete` |

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
   | When ratio reaches | `1.0` |
   | then | `Remove torrent and its files` |

   > "Remove torrent and its files" is the key setting. The hardlink
   > in your media library survives this deletion — only the download
   > copy is removed. Without this your drive fills up.

6. **Settings → Connection — Port forwarding** (when you have a
   port forwarding plan):

   | Setting | Value |
   |---------|-------|
   | Listening Port | value of `TORGUARD_FORWARDED_PORT` |
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

1. Copy the recyclarr.yml from the repo to the config directory:
   ```bash
   cp docker/arr-stack/recyclarr.yml /media/arr/config/recyclarr/recyclarr.yml
   ```

2. Create the secrets file:
   ```bash
   cat > /media/arr/config/recyclarr/secrets.yml <<EOF
   radarr_api_key: YOUR_RADARR_API_KEY
   radarr_4k_api_key: YOUR_RADARR_4K_API_KEY
   sonarr_api_key: YOUR_SONARR_API_KEY
   sonarr_4k_api_key: YOUR_SONARR_4K_API_KEY
   EOF
   chmod 600 /media/arr/config/recyclarr/secrets.yml
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
# - Incorrect WIREGUARD_PRIVATE_KEY or WIREGUARD_SERVER_PUBLIC_KEY
# - Wrong VPN_ENDPOINT_IP or VPN_ENDPOINT_PORT
# - TorGuard account not active
# Regenerate config from TorGuard client area and update .env
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