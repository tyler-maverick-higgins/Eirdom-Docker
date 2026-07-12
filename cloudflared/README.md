# Cloudflared
> Cloudflare Tunnel — Zero Inbound Ports
> Part of the Eirdom infrastructure

---

## Overview

Cloudflared creates an **outbound-only** encrypted tunnel from
EIRDOM-DOCKER-01 to Cloudflare's edge network. This is the mechanism
that makes `eirdom.homes` publicly accessible without any inbound port
forwards on the UDM-Pro-Max.

Your home IP address is never exposed in any DNS record. Even if
someone discovers it, there are zero open ports to attack.

```
Internet → Cloudflare Edge (TLS/WAF/DDoS)
               ↓
         Cloudflare Tunnel (outbound connection from cloudflared)
               ↓
         Traefik (10.1.50.10:80)
               ↓
         WordPress / Jellyfin / Jellyseerr
```

---

## Repository Structure

```
docker/cloudflared/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Create the tunnel in Cloudflare Zero Trust

1. Log into [dash.cloudflare.com](https://dash.cloudflare.com)
2. Go to **Zero Trust → Networks → Tunnels**
3. Click **Create a tunnel** → name it `Eirdom-Tunnel`
4. Select **Docker** as the connector type
5. Copy the tunnel token — it is only shown once
6. Note the Tunnel ID (UUID shown on the tunnel overview page)

### Step 2 — Configure public hostnames

In the tunnel settings → **Public Hostnames**, add:

| Subdomain | Domain | Service | Notes |
|-----------|--------|---------|-------|
| `@` | `eirdom.homes` | `http://traefik:80` | WordPress |
| `www` | `eirdom.homes` | `http://traefik:80` | WordPress www redirect |
| `jellyfin` | `eirdom.homes` | `http://traefik:80` | Jellyfin |
| `requests` | `eirdom.homes` | `http://traefik:80` | Jellyseerr |

> Traffic arrives at Traefik as plain HTTP on port 80. TLS is
> terminated at the Cloudflare edge — the tunnel connection itself
> is encrypted end-to-end by the tunnel protocol. This is correct
> and secure — do not add TLS between cloudflared and Traefik.

### Step 3 — Fill in .env

```bash
cp .env.example .env
nano .env
```

| Variable | Value |
|----------|-------|
| `CLOUDFLARE_TUNNEL_TOKEN` | Token from Step 1 |
| `CLOUDFLARE_TUNNEL_ID` | UUID from tunnel overview |

### Step 4 — Start cloudflared

Start Traefik first, then:

```bash
docker compose up -d
docker compose logs -f
```

Watch for:
```
cloudflared | Connection ... registered
cloudflared | Tunnel ... is connected
```

---

## Cloudflare Security Settings

Configure these in the Cloudflare dashboard for `eirdom.homes`:

| Setting | Value |
|---------|-------|
| SSL/TLS Mode | Full (not Full Strict — backend is HTTP) |
| Always Use HTTPS | Enabled |
| Minimum TLS Version | TLS 1.2 |
| Automatic HTTPS Rewrites | Enabled |
| Browser Integrity Check | Enabled |
| Bot Fight Mode | Enabled |
| WAF Managed Ruleset | Enabled (free tier) |

---

## Adding New Public Services

To expose an additional service externally (e.g. future external
Jellyfin access for family away from home):

1. In Zero Trust → Tunnels → Eirdom-Tunnel → Public Hostnames
2. Add the new hostname pointing to `http://traefik:80`
3. Optionally protect with a Cloudflare Access policy (free for up
   to 50 users) — requires email OTP before the request reaches
   your network

> Most services should remain internal only. Only add public
> hostnames for services that genuinely need external access.

---

## Monitoring

Check tunnel health in Cloudflare Zero Trust dashboard:

**Zero Trust → Networks → Tunnels → Eirdom-Tunnel**

The tunnel should show **Healthy** with active connectors. If it
shows **Degraded** or **Inactive**:

```bash
# Check container status
docker compose ps
docker logs cloudflared --tail 30

# Restart if needed
docker compose restart cloudflared
```

---

## Troubleshooting

### Tunnel connects but site returns 502

Traefik is not running or the WordPress container is unhealthy.
Cloudflared can reach Traefik but Traefik can't reach the backend.

```bash
cd docker/traefik && docker compose ps
cd docker/webserver && docker compose ps
```

### Tunnel token invalid

The token is single-use for display — if you've lost it, regenerate:
1. Zero Trust → Networks → Tunnels → Eirdom-Tunnel → Configure
2. Delete the existing connector and create a new one
3. Update `CLOUDFLARE_TUNNEL_TOKEN` in `.env` and restart

### DNS not resolving externally

Verify the Cloudflare DNS records for `eirdom.homes` are proxied
(orange cloud, not grey). Grey cloud records bypass the tunnel and
would expose your home IP.

---

## Related Documentation

- [`docker/traefik/README.md`](../traefik/README.md) — Traefik setup
- [`docs/services.md`](../../docs/services.md) — Service reference
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-001
- [`unifi/firewall/wan-rules.md`](../../unifi/firewall/wan-rules.md) — WAN rules (zero inbound)