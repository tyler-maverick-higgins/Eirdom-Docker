# Ntfy
> Self-Hosted Push Notifications
> Part of the Eirdom infrastructure

---

## Overview

Ntfy is the push notification backbone for the entire Eirdom stack.
Every service that needs to alert you — Uptime Kuma downtime, Wazuh
security events, backup failures, Home Assistant automations — publishes
to ntfy topics, and ntfy delivers them instantly to your phone.

**Authentication is two-layer:**
- **Web UI** — Authentik ForwardAuth (`chain-standard`)
- **Services and mobile apps** — ntfy token auth (bypasses Authentik
  entirely, connects directly to ntfy with an access token)

This separation is intentional — push notifications need to work
without a browser auth flow.

---

## Repository Structure

```
docker/ntfy/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Start the container

No `.env` values required beyond root `.env`.

```bash
cd docker/ntfy
docker compose up -d
docker compose logs -f
```

### Step 2 — Create users

```bash
# Admin user (you)
docker exec ntfy ntfy user add --role=admin tyler

# Set the password when prompted
# Save to password manager
```

### Step 3 — Generate service access tokens

Each service that publishes notifications needs its own token:

```bash
# Generate token for a user
docker exec ntfy ntfy token add tyler

# Output looks like: tk_abc123...
# Save each token to password manager
```

Use separate tokens per service so you can revoke individual ones
if needed without affecting others.

### Step 4 — Configure Uptime Kuma

In Uptime Kuma → Settings → Notifications → Add Notification:

| Field | Value |
|-------|-------|
| Type | ntfy |
| Server URL | `https://ntfy.eirdom.homes` |
| Topic | `eirdom-alerts` |
| Token | Token generated in Step 3 |

Test the notification to confirm delivery before saving.

### Step 5 — Configure mobile app

Install **ntfy** from the App Store or Google Play:

1. Open app → Add server → `https://ntfy.eirdom.homes`
2. Log in with username and password from Step 2
3. Subscribe to `eirdom-alerts`
4. Enable notifications in device settings

---

## Adding More Notification Sources

### Wazuh

Full setup in `docs/wazuh-setup.md` Phase 6. Summary — run on EIRDOM-WAZUH-01:

```bash
sudo tee /var/ossec/integrations/custom-ntfy << 'EOF'
#!/bin/bash
ALERT_FILE="$1"
NTFY_URL="https://ntfy.eirdom.homes/eirdom-security"
NTFY_TOKEN="YOUR_NTFY_TOKEN_HERE"

LEVEL=$(python3 -c "import json; d=json.load(open('$ALERT_FILE')); print(d.get('rule',{}).get('level',''))" 2>/dev/null)
DESC=$(python3 -c "import json; d=json.load(open('$ALERT_FILE')); print(d.get('rule',{}).get('description','Unknown alert'))" 2>/dev/null)
AGENT=$(python3 -c "import json; d=json.load(open('$ALERT_FILE')); print(d.get('agent',{}).get('name','Unknown'))" 2>/dev/null)

curl -s \\
    -H "Authorization: Bearer $NTFY_TOKEN" \\
    -H "Title: Wazuh Alert — Level $LEVEL" \\
    -H "Priority: high" \\
    -H "Tags: warning" \\
    -d "Agent: $AGENT | $DESC" \\
    "$NTFY_URL" > /dev/null 2>&1
exit 0
EOF
sudo chmod 750 /var/ossec/integrations/custom-ntfy
sudo chown root:wazuh /var/ossec/integrations/custom-ntfy
```

Add to `/var/ossec/etc/ossec.conf`:

```xml
<integration>
  <n>custom-ntfy</n>
  <level>12</level>
  <alert_format>json</alert_format>
</integration>
```

```bash
sudo systemctl restart wazuh-manager
```

Subscribe to `eirdom-security` in the ntfy mobile app.

Add ntfy notification to `scripts/backup.sh` at the end of the
summary section:

```bash
# Notify via ntfy on backup completion
curl -s \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Title: Eirdom Backup" \
  -d "Backup completed: ${#BACKUP_SUCCESS[@]} OK, ${#BACKUP_FAILED[@]} failed" \
  https://ntfy.eirdom.homes/eirdom-alerts
```

### Home Assistant

In HA → Settings → Integrations → Add → RESTful Notifications,
or install the ntfy HACS integration for native support.

---

## Topic Structure

Keep topics organised to avoid notification noise:

| Topic | Used For |
|-------|---------|
| `eirdom-alerts` | Uptime Kuma downtime, critical failures |
| `eirdom-security` | Wazuh security events |
| `eirdom-backup` | Backup completion/failure |
| `eirdom-home` | Home Assistant automations |

---

## Storage

All data lives in `${DOCKER_DATA_PATH}/ntfy/`:
- `cache.db` — cached notifications (12h retention)
- `auth.db` — user accounts and access tokens

Both are backed up daily by `scripts/backup.sh`.

---

## Troubleshooting

### Notifications not arriving on phone

```bash
# Verify the container is running
docker compose ps

# Test publish directly
curl -H "Authorization: Bearer YOUR_TOKEN" \
     -d "Test notification" \
     https://ntfy.eirdom.homes/eirdom-alerts
```

If the curl works but the phone doesn't receive it, check that the
ntfy app has notification permissions enabled in iOS/Android settings.

### "Unauthorized" errors from services

The token may have been deleted or the wrong topic is being used.
List active tokens:

```bash
docker exec ntfy ntfy token list tyler
```

Regenerate if needed and update the service configuration.

### Web UI not loading

Check Authentik is healthy — the web UI is protected by
`chain-standard`. If Authentik is down, the web UI is inaccessible
but services using token auth continue working normally.

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Ntfy service entry
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-036
- [`docker/uptime-kuma/README.md`](../uptime-kuma/README.md) — Uptime Kuma notification config
- [`docs/homeassistant-setup.md`](../../docs/homeassistant-setup.md) — HA notification integration