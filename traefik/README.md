# Traefik
> Reverse Proxy · TLS · Authentik ForwardAuth
> Traefik v3.3 · Part of the Eirdom infrastructure

---

## Overview

Traefik is the single ingress point for all Eirdom services. Every
request — whether arriving from the Cloudflare Tunnel or from a LAN
client — passes through Traefik before reaching a container.

**Traefik must always start before any other Docker service.**

Key responsibilities:

- **TLS termination** — wildcard cert for `*.eirdom.homes` issued via
  Let's Encrypt DNS challenge using Cloudflare API
- **HTTP → HTTPS redirect** — all HTTP traffic on port 80 is
  permanently redirected to port 443
- **Routing** — routes traffic to the correct container by `Host`
  header
- **Authentik ForwardAuth** — enforces SSO via Authentik on services
  using `chain-standard` or `chain-admin` middleware

---

## Repository Structure

```
docker/traefik/
├── docker-compose.yml
├── traefik.yml              # Static config — entrypoints, ACME, providers
├── .env.example
└── dynamic/                 # Dynamic config — loaded at runtime
    ├── middlewares.yml      # All middleware definitions and chains
    └── routers.yml          # Static routes (Proxmox, Wazuh, Sec. Onion)
```

---

## Setup

### Step 1 — Fill in .env

```bash
cp .env.example .env
nano .env
```

Required values:

| Variable | Where to find it |
|----------|-----------------|
| `TRAEFIK_ACME_EMAIL` | Your email for Let's Encrypt notifications |
| `CF_API_TOKEN` | Cloudflare → Profile → API Tokens → Edit zone DNS |
| `CF_ZONE_ID` | Cloudflare → eirdom.homes → Overview → Zone ID |

**Cloudflare API Token permissions required:**
- Zone / DNS / Edit
- Zone / Zone / Read
- Zone Resources: Specific zone → `eirdom.homes`

### Step 2 — Create acme.json

Traefik refuses to start if this file doesn't exist with exactly 600
permissions:

```bash
touch ${DOCKER_DATA_PATH}/traefik/certs/acme.json
chmod 600 ${DOCKER_DATA_PATH}/traefik/certs/acme.json
```

`provision.sh` handles this automatically on first run.

### Step 3 — Start Traefik

```bash
docker compose up -d
docker compose logs -f
```

Watch for:
- `Certificate obtained successfully` — wildcard cert issued
- `Configuration loaded from file` — dynamic configs loaded

The wildcard cert takes 30–90 seconds on first start while Traefik
completes the Cloudflare DNS challenge.

---

## Middleware Chains

Three chains are defined in `dynamic/middlewares.yml`. Apply them
via container labels:

| Chain | Middlewares | Use For |
|-------|------------|---------|
| `chain-standard` | Authentik ForwardAuth + security headers | All internal services |
| `chain-public` | Security headers + rate limit | Jellyfin, Jellyseerr, WordPress |
| `chain-admin` | Authentik + VLAN 10 whitelist + security headers | Traefik dashboard, Proxmox, Wazuh, Jellystat |

### Applying to a container

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myservice.rule=Host(`myservice.eirdom.homes`)"
  - "traefik.http.routers.myservice.entrypoints=websecure"
  - "traefik.http.routers.myservice.tls=true"
  - "traefik.http.routers.myservice.tls.certresolver=cloudflare"
  - "traefik.http.services.myservice.loadbalancer.server.port=8080"
  - "traefik.http.routers.myservice.middlewares=chain-standard"
  - "traefik.docker.network=proxy"
```

---

## Static Routes

Services not running as Docker containers are routed via
`dynamic/routers.yml`:

| Route | Target | Chain |
|-------|--------|-------|
| `traefik.eirdom.homes` | Traefik dashboard | `chain-admin` |
| `proxmox.eirdom.homes` | `https://10.1.10.5:8006` | `chain-admin` |
| `wazuh.eirdom.homes` | `https://10.1.60.10` | `chain-admin` |
| `securityonion.eirdom.homes` | `https://10.1.60.20` | `chain-admin` |

Proxmox uses a self-signed cert — the `proxmox-transport` servers
transport has `insecureSkipVerify: true`.

---

## TLS Certificate

Traefik issues a single wildcard certificate covering `*.eirdom.homes`
and `eirdom.homes` via the Let's Encrypt DNS challenge against
Cloudflare. The cert is stored in `acme.json` and auto-renewed before
expiry.

There is no Let's Encrypt configuration for individual services —
the wildcard covers everything.

**Check cert status:**

```bash
cat ${DOCKER_DATA_PATH}/traefik/certs/acme.json \
  | python3 -m json.tool | grep -A2 '"domain"'
```

---

## Troubleshooting

### Certificate not issuing

```bash
docker logs traefik --tail 50 | grep -iE "acme|certificate|error|dns"
```

- Verify `CF_API_TOKEN` has DNS edit permissions for `eirdom.homes`
- Verify `CF_ZONE_ID` matches the zone in Cloudflare dashboard
- Test the token: `curl -H "Authorization: Bearer $CF_API_TOKEN" https://api.cloudflare.com/client/v4/user/tokens/verify`

### Service returns 502 Bad Gateway

The container is not running or not healthy. Check:

```bash
docker ps | grep <service>
docker logs <service> --tail 20
```

### Authentik ForwardAuth redirect loop

The Authentik outpost URL must be `https://auth.eirdom.homes` (not
`http://`). Check in Authentik admin → Applications → Outposts →
edit embedded outpost → verify Authentik URL.

### Dashboard inaccessible from VLAN 10

Verify the `ipwhitelist-corporate` middleware in `middlewares.yml`
includes your VLAN 10 subnet (`10.1.10.0/24`). The `chain-admin`
middleware applies this whitelist.

---

## Logs

Access logs and error logs are written to
`${DOCKER_DATA_PATH}/traefik/logs/` and forwarded to Wazuh for
analysis. The access log filters out 2xx/3xx responses — only 4xx/5xx
errors and slow requests are retained to keep log volume manageable.

---

## Related Documentation

- [`authentik/README.md`](../authentik/README.md) — ForwardAuth setup
- [`docs/services.md`](../../docs/services.md) — Service reference
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-006, ADR-007
- [`unifi/firewall/lan-rules.md`](../../unifi/firewall/lan-rules.md) — Firewall rules