# Uptime Kuma
> Service Monitoring · Status Dashboard
> Part of the Eirdom infrastructure

---

## Overview

Uptime Kuma monitors every Eirdom service and alerts when something
goes down. It is the first place to check when a service is
unreachable — before SSHing into the server or checking logs.

- **HTTP monitors** — pings every service URL and expects a 2xx response
- **TCP monitors** — verifies critical infrastructure ports (DNS, LDAP)
- **Docker socket** — reads container health directly (read-only mount)
- **Notifications** — push or email alerts when a monitor goes down

Uptime Kuma has its own internal login, but Authentik ForwardAuth sits
in front of it so the login page is never exposed.

---

## Repository Structure

```
docker/uptime-kuma/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Start the container

No `.env` values are required beyond what the root `.env` provides.

```bash
cd docker/uptime-kuma
docker compose up -d
docker compose logs -f
```

### Step 2 — Create admin account

Navigate to `https://status.eirdom.homes`.

You will be prompted to create an admin username and password on first
visit. Set a strong password and save it to your password manager.

> Authentik ForwardAuth protects the outer layer, but Uptime Kuma's
> own login is a second layer — keep both active.

### Step 3 — Configure notification channel

Before adding monitors, set up at least one notification channel so
alerts actually reach you. Without this, downtime is logged silently.

Settings → Notifications → Add Notification:

| Type | Recommended For |
|------|----------------|
| Email (SMTP) | General alerts — uses root .env SMTP settings |
| Ntfy | Push notifications to phone |
| Telegram | Instant mobile alerts |
| Gotify | Self-hosted push (if deployed) |

Test the notification before proceeding.

### Step 4 — Add monitors

Add a monitor for every Eirdom service. Recommended configuration:

**HTTP(s) monitors** — set Heartbeat Interval to 60 seconds,
Retries to 2 before alerting (avoids false alarms on brief restarts):

| Name | URL | Expected Status |
|------|-----|----------------|
| WordPress | `https://eirdom.homes` | 200 |
| Traefik | `https://traefik.eirdom.homes` | 200 |
| Authentik | `https://auth.eirdom.homes` | 200 |
| Jellyfin | `https://jellyfin.eirdom.homes/health` | 200 |
| Jellyseerr | `https://requests.eirdom.homes` | 200 |
| Radarr | `https://radarr.eirdom.homes` | 200 |
| Sonarr | `https://sonarr.eirdom.homes` | 200 |
| Prowlarr | `https://prowlarr.eirdom.homes` | 200 |
| Lidarr | `https://lidarr.eirdom.homes` | 200 |
| Bazarr | `https://bazarr.eirdom.homes` | 200 |
| qBittorrent | `https://qbit.eirdom.homes` | 200 |
| NetBox | `https://netbox.eirdom.homes` | 200 |
| Jellystat | `https://jellystat.eirdom.homes` | 200 |
| Paperless | `https://paperless.eirdom.homes` | 200 |
| Immich | `https://photos.eirdom.homes` | 200 |
| Wazuh | `https://wazuh.eirdom.homes` | 200 |

**TCP monitors** — for infrastructure that doesn't have a web UI:

| Name | Host | Port | Purpose |
|------|------|------|---------|
| DC-01 DNS | 10.1.10.10 | 53 | AD DNS — everything breaks if this is down |
| DC-01 LDAP | 10.1.10.10 | 389 | AD auth — Authentik, NetBox, Jellyfin |
| DC-01 RDP | 10.1.10.10 | 3389 | DC reachability check |

---

## Storage

Uptime Kuma stores everything in a single SQLite database at
`${DOCKER_DATA_PATH}/uptime-kuma/kuma.db`. This includes all monitor
configurations, history, and notification settings.

Backed up daily by `scripts/backup.sh` as part of the
`uptime-kuma` tar.gz — the entire data directory is included.

---

## Troubleshooting

### Monitor shows DOWN but service is actually up

Check whether the URL requires authentication. Uptime Kuma hits the
URL directly — if Authentik ForwardAuth redirects to the login page,
Uptime Kuma gets a 302 and may report it as down depending on your
expected status code configuration.

Fix: either set the expected status code to `200-302`, or use a
health-check endpoint that bypasses auth (e.g. Jellyfin's
`/health` endpoint).

### Docker socket monitors not working

Verify the socket mount is present and the container is running:

```bash
docker compose ps
docker exec uptime-kuma ls /var/run/docker.sock
```

### Notifications not sending

Test the notification channel from Settings → Notifications →
(channel) → Test. Check SMTP credentials in the root `.env` if
using email.

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Uptime Kuma service entry
- [`docs/deployment-guide.md`](../../docs/deployment-guide.md) — Phase 15 setup
- [`docker/traefik/README.md`](../traefik/README.md) — Traefik middleware chains