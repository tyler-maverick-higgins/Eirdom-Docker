# Immich
> Family Photo & Video Backup — Private Google Photos
> Part of the Eirdom infrastructure

---

## Overview

Immich is the family photo and video library. Everyone's phone
automatically backs up photos to the home server. Albums, faces,
and memories stay on your own hardware — not on Apple or Google's
servers.

**Key features:**
- Automatic background backup from iOS and Android
- Face recognition and people grouping (CPU-based, slower than GPU)
- CLIP semantic search — search by description ("dog at the beach")
- Shared albums across family members
- Timeline view, map view, memories ("On this day")
- Works both at home (LAN) and away (via Cloudflare Tunnel)

**Authentication:** Immich handles its own auth — email + password.
`chain-public` middleware is used because the Immich mobile apps
initiate direct API connections that cannot go through Authentik
ForwardAuth.

---

## Repository Structure

```
docker/immich/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Fill in .env

```bash
cd docker/immich
cp .env.example .env
nano .env
```

| Variable | How to Generate |
|----------|----------------|
| `IMMICH_DB_PASSWORD` | `openssl rand -base64 32` |

### Step 2 — Start the stack

```bash
docker compose up -d
docker compose logs -f immich-server
```

**First start takes longer than other services.** The
`immich-machine-learning` container downloads ML models (~1GB) on
first run. Wait for both of these lines before proceeding:

```
immich-server          | Immich Server is listening on...
immich-machine-learning| Application is ready
```

### Step 3 — Create the admin account

Navigate to `https://photos.eirdom.homes`.

**The first account registered becomes the permanent admin.**
Create your own account before sharing the URL with family.

Set a strong password and save to password manager.

### Step 4 — Invite family members

Administration → Users → Create User for each family member:
- Fill in their name and email
- Set a temporary password (they can change it on first login)
- Or enable "Require password change on first login"

### Step 5 — Configure the Cloudflare Tunnel public hostname

If not already done in the main Traefik/Cloudflare setup, add the
`photos` hostname to the tunnel:

Zero Trust → Networks → Tunnels → Eirdom-Tunnel → Public Hostnames:
- Subdomain: `photos`
- Domain: `eirdom.homes`
- Service: `http://traefik:80`

This enables backup from phones when away from home.

---

## Mobile App Setup

Share these steps with family members.

**iOS and Android:**

1. Install **Immich** from the App Store or Google Play
2. Open the app → **Getting Started** → **Server endpoint**
3. Enter: `https://photos.eirdom.homes`
4. Log in with the email and password from your invite
5. Tap the profile icon → **Backup** → **Auto Backup** → Enable

**Recommended backup settings:**
- Background backup: Enabled
- WiFi only: Enabled (saves mobile data)
- Charging only: Optional (recommended for large initial backups)

The initial backup of an existing photo library can take several
hours to days depending on library size — this is normal.

---

## Storage Layout

```
${MEDIA_PATH}/immich/
├── library/      Processed photo/video files (permanent storage)
├── upload/       Upload staging area (temporary)
├── thumbs/       Generated thumbnails (regeneratable)
├── profile/      Profile photos
└── video/        Transcoded video (regeneratable)

${DOCKER_DATA_PATH}/immich/
├── db/           PostgreSQL database (pgvecto.rs)
└── ml-cache/     Downloaded ML models (~1GB, cached after first run)
```

---

## Backup Strategy

**What is backed up** (`scripts/backup.sh` daily):
- PostgreSQL database dump — all albums, faces, tags, shared albums,
  user accounts, and all metadata

**What is NOT backed up:**
- The photo and video library (`${MEDIA_PATH}/immich/library/`)
- Thumbnails and transcoded video (regeneratable)

**Why the library is excluded:**

The library can be very large (hundreds of GB for a full family
archive) and all source photos already exist on family devices.
In a disaster recovery scenario, the library can be re-imported
from phones. The DB backup preserves all the organisation work —
albums, faces, tags — so re-importing only requires the photos
themselves, not re-doing all the categorisation.

> If you want the library backed up, configure a separate rsync or
> rclone job to an external drive or NAS. This is intentionally
> outside `backup.sh` scope.

---

## Machine Learning Features

The `immich-machine-learning` container runs on CPU only — the
Xeon X3430 has no GPU. This means:

- **Face recognition** — works but runs slower. New faces are
  detected and grouped overnight rather than immediately
- **CLIP search** — semantic search ("photos of the backyard")
  works but indexing takes longer after large uploads
- **Smart albums** — motion, blurred photos detection works normally

This is expected behaviour — not a problem to fix, just a
characteristic of CPU-only ML inference.

---

## Troubleshooting

### Mobile app can't connect

1. Verify `https://photos.eirdom.homes` is reachable from outside
   the home — check Cloudflare Tunnel status in Zero Trust dashboard
2. Check the Immich server is running: `docker compose ps`
3. Verify the Cloudflare public hostname is configured for `photos`

### Upload fails or pauses

Large video files can time out on slow connections. The app will
automatically retry — leave it running. For the initial library
import, connect to home WiFi for best results.

### Face recognition not working

The ML container may still be processing. Check its status:

```bash
docker logs immich-machine-learning --tail 20
```

Face detection runs as a background job — it processes new photos
in batches. Go to Administration → Jobs → Face Detection → Run
to trigger it manually.

### "Wrong password" after password reset

Immich caches sessions. Clear the app's storage or log out and back
in after a password change.

---

## Upgrading Immich

Immich releases frequently. Always check the
[release notes](https://github.com/immich-app/immich/releases) before
upgrading — breaking changes are clearly marked.

```bash
cd docker/immich
docker compose pull
docker compose up -d
```

`scripts/update.sh` handles this automatically as part of the
weekly update cycle.

> **Important:** Immich occasionally requires database migrations on
> upgrade. The migration runs automatically on container start. Do not
> interrupt the container during first startup after an upgrade.

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Immich service entry
- [`docs/family-setup.md`](../../docs/family-setup.md) — Family guide (add photos section)
- [`docs/deployment-guide.md`](../../docs/deployment-guide.md) — Phase 15 setup
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-035