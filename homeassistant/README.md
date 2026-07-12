# Home Assistant
> Smart Home Hub · Family Dashboard · Automation Engine
> Part of the Eirdom infrastructure

---

## Overview

Home Assistant runs as **HA Container** on EIRDOM-DOCKER-01 —
one of the two officially supported installation methods
(alongside HAOS) since Core and Supervised were deprecated in
2025.12. This supersedes the ADR-041 plan for a HAOS VM on
Proxmox. Rationale: full integration access is identical across
install methods; the add-on store is the only loss, and every
planned add-on (Mosquitto, Zigbee2MQTT, Node-RED) is an ordinary
container better managed in this repo's compose/backup/Wazuh
patterns; and it removes a 4 GB VM reservation from the
RAM-constrained Proxmox host.

**Terminology:** *integrations* (Mealie, UniFi Protect, Jellyfin,
Ntfy, ZHA) are HA core and work here fully. *Add-ons* are a
HAOS/Supervisor feature and become companion containers instead
(see table below).

---

## Repository Structure

```
docker/homeassistant/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Start the container

```bash
mkdir -p ${DOCKER_DATA_PATH}/homeassistant
cd docker/homeassistant
docker compose up -d
docker compose logs -f
```

HA binds directly on the host (network_mode: host):
`http://10.1.50.10:8123`

### Step 2 — Onboarding

Open `http://10.1.50.10:8123`. **The first account created is the
owner** — create yours before sharing any URL with family. Save
credentials to the password manager. Family accounts are added
later under Settings → People (non-admin).

### Step 3 — Reverse proxy trust (REQUIRED)

HA rejects proxied requests (400 Bad Request) unless the proxy
is trusted. Find the `proxy` network subnet:

```bash
docker network inspect proxy \
  --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'
```

Add to `${DOCKER_DATA_PATH}/homeassistant/configuration.yaml`
(use the subnet the command returned):

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.18.0.0/16   # ← proxy network subnet from above
    - 127.0.0.1
    - ::1
```

Then `docker compose restart`.

### Step 4 — Update the Traefik route

`docker/traefik/dynamic/routers.yml` already contains the
`homeassistant` router (chain-public — correct, HA handles its
own auth and the companion app cannot pass ForwardAuth). Only
the **service block** changes: the old target was the HAOS VM
over self-signed HTTPS; the container serves plain HTTP on the
Docker host.

Replace the existing `homeassistant-svc` block with:

```yaml
    # -----------------------------------------------------------
    # Home Assistant (Container on EIRDOM-DOCKER-01)
    # Plain HTTP on the host — no serversTransport needed
    # -----------------------------------------------------------
    homeassistant-svc:
      loadBalancer:
        servers:
          - url: "http://10.1.50.10:8123"
```

Also update the router comment (remove the HAOS self-signed
cert note). The file provider picks this up without a restart.

> **Verify once during deployment:** the dynamic files use
> `${ROOT_DOMAIN}` in Host rules. Traefik's file provider does
> Go templating, not shell-style expansion — if the existing
> file-provider routes (e.g. `traefik.eirdom.homes`) resolve,
> interpolation is handled and this note is moot. If they
> don't, hardcode the domain in `routers.yml`.

### Step 5 — Companion apps

Install **Home Assistant** (App Store / Google Play).
Server URL: `https://homeassistant.eirdom.homes`

Internal DNS resolves this to Traefik; remote access rides the
existing WireGuard full-tunnel — no cloud subscription, no
exposure via the Cloudflare Tunnel.

---

## Integrations

Full walkthroughs in `docs/homeassistant-setup.md` Phase 5
(UniFi Protect, Jellyfin, Ntfy). Additions for the home
management workflow:

### Mealie

Mealie → user profile → Manage Your API Tokens → create token
named `Home Assistant`. Then HA → Settings → Devices & Services
→ Add → Mealie → `https://mealie.eirdom.homes` + token.

Provides: a to-do entity per Mealie shopping list (5-min sync),
meal-plan calendars, and actions including `mealie.import_recipe`
and `mealie.set_random_mealplan` (used by the Friday auto-fill
automation in `docs/workflows.md`).

### Ntfy

Publish HA automations to `eirdom-home` per the existing topic
table — RESTful notify or the ntfy HACS integration
(`docs/homeassistant-setup.md` Phase 5).

---

## Former Add-ons → Companion Containers

Deploy only on demonstrated need (ADR-003):

| HAOS Add-on | Container replacement | Trigger to deploy |
|-------------|----------------------|-------------------|
| Mosquitto | `eclipse-mosquitto` | First MQTT device |
| Zigbee2MQTT | `koenkk/zigbee2mqtt` | Zigbee coordinator arrives |
| Matter Server | verify current image — server was rebuilt on matter.js in 2026.7 | First Matter device |
| Node-RED | `nodered/node-red` | Automation outgrows the native editor |
| File Editor / SSH | not needed — you own the host | — |

Zigbee note: pass the dongle with an explicit `devices:` entry
(template commented in compose) — physical host, no hypervisor
passthrough required.

---

## Updates

Image is pinned to an exact version (`2026.7.1`) — deliberate
deviation from the repo's `:latest` habit, because HA ships
monthly with breaking changes.

- **Patch bumps (2026.7.x):** Fridays, bugfix-only — edit the
  tag and `docker compose up -d` freely.
- **Minor bumps (2026.X):** read the release-notes breaking
  changes section first, then bump.

---

## Storage & Backup

All state in `${DOCKER_DATA_PATH}/homeassistant/` — covered by
`scripts/backup.sh` daily. HA's built-in backup system also
works on Container installs and can be pointed at a network
target later if desired; the volume backup is the baseline.

---

## Troubleshooting

### 400 Bad Request via homeassistant.eirdom.homes

`trusted_proxies` missing or wrong subnet — Step 3.

### Direct IP works, hostname doesn't

File-provider route not applied — check `routers.yml` syntax
and the `${ROOT_DOMAIN}` interpolation note in Step 4.

### Devices on the IoT VLAN aren't discovered

mDNS doesn't cross VLANs by default. Enable multicast DNS
reflection between VLAN 50 and VLAN 20 on the UDM (UniFi
Network → Settings → Networks → Multicast DNS). Required
regardless of install method.

### Companion app can't connect remotely

Confirm the WireGuard tunnel is up — the hostname is internal
only and intentionally not published through the Cloudflare
Tunnel.

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — add HA service entry
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-041 (supersede with Container rationale)
- [`docs/homeassistant-setup.md`](../../docs/homeassistant-setup.md) — Phases 1/17 (VM build) to be rewritten for Container; Phase 5 integrations still apply
- [`docs/workflows.md`](../../docs/workflows.md) — family workflow this hub serves
