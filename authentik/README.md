# Traefik + Authentik
> Reverse Proxy · TLS · SSO
> Part of the Eirdom infrastructure

---

## Overview

This document covers both the Traefik and Authentik stacks, which
are tightly coupled and must be deployed together.

- **Traefik v3.3** — reverse proxy, wildcard TLS via Let's Encrypt
  DNS challenge, HTTP→HTTPS redirect, routes all traffic by hostname
- **Authentik 2026.2** — identity provider, SSO via ForwardAuth,
  Active Directory LDAP integration

**Start order:** Traefik → Authentik → everything else

---

## Repository Structure

```
docker/
├── traefik/
│   ├── docker-compose.yml
│   ├── traefik.yml           # Static config
│   ├── .env.example
│   └── dynamic/              # Dynamic config — loaded at runtime
│       ├── middlewares.yml   # All middlewares and chains
│       └── routers.yml       # Non-Docker routes (Proxmox, Wazuh, etc.)
│
└── authentik/
    ├── docker-compose.yml
    └── .env.example
```

---

## Folder Setup on the Server

Run these once after cloning. `provision.sh` creates most directories
but the Traefik dynamic config directory needs the files copied in:

```bash
# Create Traefik config directories
mkdir -p ${DOCKER_DATA_PATH}/traefik/certs
mkdir -p ${DOCKER_DATA_PATH}/traefik/logs

# Set correct permissions on acme.json
# Traefik refuses to start if this file is not exactly 600
touch ${DOCKER_DATA_PATH}/traefik/certs/acme.json
chmod 600 ${DOCKER_DATA_PATH}/traefik/certs/acme.json

# Create Authentik directories
mkdir -p ${DOCKER_DATA_PATH}/authentik/postgres
mkdir -p ${DOCKER_DATA_PATH}/authentik/media
mkdir -p ${DOCKER_DATA_PATH}/authentik/templates
mkdir -p ${DOCKER_DATA_PATH}/authentik/certs

chown -R 1000:1000 ${DOCKER_DATA_PATH}/traefik
chown -R 1000:1000 ${DOCKER_DATA_PATH}/authentik
```

---

## Phase 1 — Deploy Traefik

### Step 1 — Fill in Traefik .env

```bash
cd docker/traefik
cp .env.example .env
nano .env
```

Required values:
- `TRAEFIK_ACME_EMAIL` — your email for Let's Encrypt notifications
- `CF_API_TOKEN` — Cloudflare API token with DNS edit permissions
- `CF_ZONE_ID` — your Cloudflare zone ID for `eirdom.homes`

**Creating the Cloudflare API token:**
1. Go to `dash.cloudflare.com` → Profile → API Tokens
2. Create Token → Edit zone DNS (template)
3. Permissions: Zone / DNS / Edit + Zone / Zone / Read
4. Zone Resources: Specific zone → `eirdom.homes`
5. Copy the token — it is only shown once

### Step 2 — Copy dynamic config files to the repo folder

The dynamic config files (`middlewares.yml`, `routers.yml`) live in
`docker/traefik/dynamic/` in the repo. Traefik reads them from that
path via the volume mount in `docker-compose.yml`.

Confirm the files exist:

```bash
ls docker/traefik/dynamic/
# Should show: middlewares.yml  routers.yml
```

### Step 3 — Start Traefik

```bash
cd docker/traefik
docker compose up -d
docker compose logs -f
```

Watch for:
- `Traefik provisioned with the certificate` — TLS cert issued
- `Configuration loaded from file` — dynamic configs loaded
- No `error` entries in the log output

The wildcard cert for `*.eirdom.homes` takes 30–90 seconds to issue
on first start while Traefik completes the DNS challenge with
Cloudflare. You will see log entries about DNS propagation — this
is normal.

### Step 4 — Verify Traefik is running

```bash
# Check container status
docker compose ps

# Test HTTPS redirect (should get 301 redirect to https)
curl -I http://eirdom.homes

# Check acme.json has content (cert was issued)
cat ${DOCKER_DATA_PATH}/traefik/certs/acme.json | python3 -m json.tool | grep -c "certificate"
# Should return a number > 0
```

> The Traefik dashboard at `https://traefik.eirdom.homes` will return
> a 502 until Authentik is running — this is expected. The Authentik
> ForwardAuth middleware is already in the middleware chain, so Traefik
> correctly tries to authenticate the request and fails since Authentik
> is not yet available.

---

## Phase 2 — Deploy Authentik

### Step 1 — Fill in Authentik .env

```bash
cd docker/authentik
cp .env.example .env
nano .env
```

Generate the required secrets:

```bash
# Generate AUTHENTIK_DB_PASSWORD
openssl rand -base64 32

# Generate AUTHENTIK_SECRET_KEY
# CRITICAL: Generate once and never change after first start
# Changing this key invalidates ALL existing user sessions
openssl rand -base64 60
```

Store both values in your password manager before adding them to
`.env`.

### Step 2 — Start Authentik

```bash
cd docker/authentik
docker compose up -d
docker compose logs -f
```

Watch for:
- `authentik-postgres` → `database system is ready to accept connections`
- `authentik-server` → `Starting server`
- `authentik-worker` → `Worker running`

First start takes 2–3 minutes while the database schema is created.

### Step 3 — Complete initial Authentik setup

1. Navigate to `https://auth.eirdom.homes/if/flow/initial-setup/`
2. Create the initial admin account:
   - Email: your admin email
   - Password: store in password manager
3. Log in to the admin interface at `https://auth.eirdom.homes`

### Step 4 — Configure the Embedded Outpost

The embedded outpost handles ForwardAuth for Traefik. It is created
automatically but needs to be configured.

1. In Authentik admin → **Applications → Outposts**
2. Click the default **authentik Embedded Outpost**
3. Click **Edit**
4. Set the **Authentik URL** to `https://auth.eirdom.homes`
5. Save

### Step 5 — Create the Traefik ForwardAuth Provider

1. In Authentik admin → **Applications → Providers**
2. Click **Create** → Select **Proxy Provider**
3. Configure:
   - Name: `Traefik ForwardAuth`
   - Authorization flow: `default-provider-authorization-implicit-consent`
   - Forward auth (domain level): enabled
   - Cookie domain: `eirdom.homes`
4. Save

### Step 6 — Create the Traefik Application

1. In Authentik admin → **Applications → Applications**
2. Click **Create**
3. Configure:
   - Name: `Eirdom Internal Services`
   - Slug: `eirdom-internal`
   - Provider: `Traefik ForwardAuth` (from Step 5)
4. Save
5. Go back to **Outposts** → edit the embedded outpost → add this
   application to the outpost

---

## Phase 3 — Configure Active Directory LDAP Source

This connects Authentik to EIRDOM-DC-01 so users authenticate with
their AD credentials.

### Step 1 — Create a service account in AD

On EIRDOM-DC-01, open Active Directory Users and Computers:

1. Navigate to `OU=Service Accounts,OU=Eirdom,DC=ad,DC=eirdom,DC=homes`
2. Create a new user:
   - First name: `Authentik`
   - User logon name: `authentik-svc`
   - Password: generate strong password, store in password manager
   - Uncheck "User must change password at next logon"
   - Check "Password never expires"
3. The account needs read-only access to the directory. Add it to the
   built-in **Domain Users** group only — no elevated privileges needed.

### Step 2 — Configure the LDAP Source in Authentik

1. In Authentik admin → **Directory → Federation & Social Login**
2. Click **Create** → Select **LDAP Source**
3. Configure:

| Field | Value |
|-------|-------|
| Name | `Eirdom Active Directory` |
| Slug | `eirdom-ad` |
| Server URI | `ldap://10.1.10.10` |
| Bind CN | `CN=authentik-svc,OU=Service Accounts,OU=Eirdom,DC=ad,DC=eirdom,DC=homes` |
| Bind password | Service account password from password manager |
| Base DN | `DC=ad,DC=eirdom,DC=homes` |
| User query filter | `(&(objectClass=user)(!(objectClass=computer)))` |
| Group query filter | `(objectClass=group)` |
| User object filter | `(objectClass=user)` |
| Group object filter | `(objectClass=group)` |
| User membership field | `member` |
| Object uniqueness field | `objectSid` |
| Sync users | Enabled |
| Sync groups | Enabled |

4. Save and click **Run sync** to perform the initial user sync
5. Check **Directory → Users** — AD users should appear

### Step 3 — Configure LDAP attribute mappings

Authentik needs to map AD attributes to its user model.

1. In Authentik admin → **Directory → Property Mappings**
2. Verify the following built-in LDAP mappings exist:
   - `authentik default LDAP Mapping: Name`
   - `authentik default LDAP Mapping: mail`
   - `authentik default LDAP Mapping: samAccountName`
3. Edit the LDAP source → **User property mappings** → add all three

### Step 4 — Test AD authentication

1. Open a private browser window
2. Navigate to `https://auth.eirdom.homes`
3. Log in with an AD user account (username@ad.eirdom.homes or
   just the username depending on your flow configuration)
4. Authentication should succeed and redirect to the user dashboard

---

## Phase 4 — Protect Services with ForwardAuth

Services are protected by adding middleware labels to their compose
files. Three middleware chains are available — use the appropriate
one per service.

### Middleware chains

| Chain | Middlewares | Use For |
|-------|------------|---------|
| `chain-standard` | Authentik + security headers | Internal services (Radarr, Sonarr, etc.) |
| `chain-public` | Security headers + rate limit | Public services (WordPress, Jellyfin) |
| `chain-admin` | Authentik + VLAN 10 whitelist + security headers | Admin UIs (Traefik dashboard, Adminer, Proxmox) |

### Adding ForwardAuth to a service

Add the middleware label to any service's compose file:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.sonarr.rule=Host(`sonarr.${ROOT_DOMAIN}`)"
  - "traefik.http.routers.sonarr.entrypoints=websecure"
  - "traefik.http.routers.sonarr.tls=true"
  - "traefik.http.routers.sonarr.tls.certresolver=cloudflare"
  - "traefik.http.services.sonarr.loadbalancer.server.port=8989"
  # Apply standard chain — Authentik SSO protection
  - "traefik.http.routers.sonarr.middlewares=chain-standard"
```

### Services that manage their own auth (opt out of Authentik)

Jellyfin and Jellyseerr have their own user authentication. They use
`chain-public` instead of `chain-standard`:

```yaml
labels:
  - "traefik.http.routers.jellyfin.middlewares=chain-public"
```

This applies security headers and rate limiting but skips Authentik
ForwardAuth — Jellyfin handles login itself.

---

## Upgrading

> **CRITICAL:** Authentik does not support downgrading. Always back
> up the PostgreSQL database before upgrading. Never skip major
> versions — upgrade sequentially (e.g. 2026.2 → 2026.4, not
> 2026.2 → 2026.8).

### Upgrading Traefik

1. Check the Traefik changelog at `doc.traefik.io/traefik/migration/v3/`
2. Update the image tag in `docker-compose.yml`
3. Commit the change to Git
4. Run `sudo bash scripts/update.sh traefik`

### Upgrading Authentik

1. Read the release notes at `docs.goauthentik.io/releases/`
2. Back up the Authentik PostgreSQL database:
   ```bash
   docker exec authentik-postgres pg_dump -U authentik authentik > \
     ${BACKUP_PATH}/authentik-pre-upgrade-$(date +%Y%m%d).sql
   ```
3. Update the image tag in `docker-compose.yml` for both
   `authentik-server` and `authentik-worker` — they must match
4. Commit the change to Git
5. Run `sudo bash scripts/update.sh authentik`
6. Watch logs for migration completion:
   ```bash
   docker logs authentik-server -f | grep -E "migration|error|ready"
   ```

---

## Troubleshooting

### Traefik dashboard returns 502

Authentik is not running or not healthy. The ForwardAuth middleware
blocks access when Authentik is unreachable.

```bash
docker compose -f docker/authentik/docker-compose.yml ps
docker logs authentik-server --tail 30
```

### Certificate not issuing

Check Cloudflare API token has correct permissions and the zone ID
matches `eirdom.homes`.

```bash
docker logs traefik --tail 50 | grep -i "acme\|certificate\|error"
```

If you see `DNS challenge failed` — verify the API token can create
TXT records:
```bash
# Test the token manually
curl -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
  -H "Authorization: Bearer ${CF_API_TOKEN}"
# Should return HTTP 200 with your DNS records
```

### LDAP sync not working

```bash
# Check Authentik worker logs for LDAP errors
docker logs authentik-worker --tail 50 | grep -i "ldap\|sync\|error"
```

Common issues:
- Service account password incorrect — verify in AD
- LDAP port blocked — check VLAN 10 firewall allows LDAP from
  DOCKER (10.1.50.0/24) to CORPORATE (10.1.10.10) on port 389
- Base DN incorrect — must match your AD forest exactly

### AD users cannot log in to Authentik

1. Verify the LDAP sync completed — check **Directory → Users** in
   Authentik admin for the AD users
2. Check the authentication flow logs in Authentik admin →
   **Events → Log**
3. Confirm the user's AD account is not disabled or locked

### Service protected by Authentik redirects to login loop

The Authentik outpost URL in the embedded outpost config must match
the external URL exactly. If it is set to `http://` instead of
`https://`, the redirect after login will fail.

1. In Authentik admin → **Applications → Outposts**
2. Edit the embedded outpost
3. Verify **Authentik URL** is `https://auth.eirdom.homes` (https, no trailing slash)

---

## Related Documentation

- [`services.md`](../../docs/services.md) — Service URLs and ports
- [`decisions.md`](../../docs/decisions.md) — ADR-006, ADR-007 (Traefik decisions)
- [`lan-rules.md`](../../unifi/firewall/lan-rules.md) — Firewall rules
- [`network-diagram.md`](../../docs/network-diagram.md) — Network topology