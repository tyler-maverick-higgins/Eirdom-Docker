# NetBox
> Network Documentation & IPAM
> NetBox v4.5 · netbox_unifi_sync plugin · AD LDAP authentication
> Part of the Eirdom infrastructure

---

## Overview

NetBox is the source of truth for all network documentation in the
Eirdom infrastructure. It tracks IP addresses, VLANs, devices,
cables, rack layouts, and network topology.

**Key integrations:**
- **Active Directory** — users authenticate with AD credentials
- **netbox_unifi_sync** — automatically syncs UniFi devices, VLANs,
  WLANs, and DHCP scopes from the UDM-Pro-Max into NetBox
- **Device Type Library** — community device type definitions for
  all Eirdom hardware (Ubiquiti, servers, switches, etc.)

**Sync direction:** UniFi → NetBox only. No data is ever written
back to UniFi.

**URL:** `https://netbox.eirdom.homes` (internal only — not exposed
through Cloudflare Tunnel)

---

## Repository Structure

```
docker/netbox/
├── docker-compose.yml
├── Dockerfile            # Custom image with netbox_unifi_sync plugin
├── configuration.py      # NetBox config — LDAP, plugins, settings
└── .env.example
```

---

## Architecture Notes

### Custom Docker Image

NetBox uses a custom image built from `Dockerfile`. The stock
`netboxcommunity/netbox` image is used as the base, with the
`netbox_unifi_sync` plugin installed on top.

This is required because the plugin must exist in the same image
used by all three NetBox containers (netbox, netbox-worker,
netbox-housekeeping). If any container uses the stock image without
the plugin, the worker's sync jobs will fail.

The custom image is tagged `eirdom/netbox:v4.5` and is built locally
— it is not pushed to any registry.

### Four Containers

| Container | Role |
|-----------|------|
| `netbox-postgres` | PostgreSQL database |
| `netbox-redis` | Task queue (Valkey/Redis compatible) |
| `netbox` | Main web application |
| `netbox-worker` | Background jobs — UniFi sync, webhooks |
| `netbox-housekeeping` | Daily cleanup — sessions, changelogs |

---

## Phase 1 — Pre-Deployment Setup

### Step 1 — Create AD Service Account

On EIRDOM-DC-01, create a dedicated read-only service account for
NetBox LDAP binding:

1. Open Active Directory Users and Computers
2. Navigate to `OU=Service Accounts,OU=Eirdom,DC=ad,DC=eirdom,DC=homes`
3. Create new user:
   - Name: `NetBox Service`
   - User logon name: `netbox-svc`
   - Password: generate strong password, store in password manager
   - Uncheck "User must change password at next logon"
   - Check "Password never expires"
4. No elevated permissions needed — Domain Users read access is
   sufficient for LDAP searches

### Step 2 — Create AD Security Groups

Create the following groups in
`OU=Security Groups,OU=Groups,OU=Eirdom,DC=ad,DC=eirdom,DC=homes`:

| Group Name | NetBox Role | Who Gets This |
|------------|------------|---------------|
| `NetBox-Users` | Can log in | All family members who use NetBox |
| `NetBox-Staff` | Staff access | Tyler (admin) |
| `NetBox-Admins` | Superuser | Tyler (admin) |

### Step 3 — Create Read-Only UniFi Account

NetBox syncs from UniFi using a dedicated read-only local account on
the UDM-Pro-Max. Do not use your admin account.

1. In UniFi Network → Settings → Admins & Users
2. Add new admin:
   - Username: `netbox-sync`
   - Role: **Read Only**
   - Password: generate strong password, store in password manager
3. Note the credentials — you will enter them in the NetBox UI
   after initial setup

### Step 4 — Create data directories

```bash
mkdir -p ${DOCKER_DATA_PATH}/netbox/postgres
mkdir -p ${DOCKER_DATA_PATH}/netbox/redis
mkdir -p ${DOCKER_DATA_PATH}/netbox/media
mkdir -p ${DOCKER_DATA_PATH}/netbox/reports
mkdir -p ${DOCKER_DATA_PATH}/netbox/scripts
chown -R 1000:1000 ${DOCKER_DATA_PATH}/netbox
```

### Step 5 — Fill in .env

```bash
cd docker/netbox
cp .env.example .env
nano .env
```

Generate required secrets:

```bash
# NETBOX_DB_PASSWORD
openssl rand -base64 32

# NETBOX_REDIS_PASSWORD
openssl rand -base64 32

# NETBOX_SECRET_KEY — generate once, never change after first start
openssl rand -base64 50
```

Store all three in your password manager before adding to `.env`.

---

## Phase 2 — Build and Start

### Step 1 — Build the custom image

```bash
cd docker/netbox
docker compose build
```

This pulls the base NetBox image and installs the `netbox_unifi_sync`
plugin. First build takes 2–3 minutes. Watch for:

```
Successfully installed netbox-unifi-sync
```

### Step 2 — Start the stack

```bash
docker compose up -d
docker compose logs -f
```

Watch for:
- `netbox-postgres` → `database system is ready to accept connections`
- `netbox-redis` → `Ready to accept connections`
- `netbox` → `Starting development server` or `Gunicorn ready`

First start takes 60–90 seconds while database migrations run.

### Step 3 — Run database migrations

On first start, NetBox automatically runs migrations. Verify:

```bash
docker exec netbox /opt/netbox/venv/bin/python \
  /opt/netbox/netbox/manage.py migrate --check
```

Should return with no pending migrations.

Run the UniFi sync plugin migrations explicitly:

```bash
docker exec netbox /opt/netbox/venv/bin/python \
  /opt/netbox/netbox/manage.py migrate netbox_unifi_sync
```

### Step 4 — Create initial superuser

On very first deployment, create a local superuser before LDAP is
fully configured. You can delete this account after confirming LDAP
login works.

```bash
docker exec -it netbox /opt/netbox/venv/bin/python \
  /opt/netbox/netbox/manage.py createsuperuser
```

---

## Phase 3 — Initial NetBox Configuration

### Step 1 — Add a Site

Before syncing from UniFi, NetBox needs a site to assign devices to.

1. Navigate to `https://netbox.eirdom.homes`
2. Log in with the superuser created above
3. Go to **Organization → Sites → Add**
4. Configure:
   - Name: `Eirdom`
   - Slug: `eirdom`
   - Status: Active
   - Physical address: your address
5. Save

### Step 2 — Import Device Types from Community Library

The Device Type Library provides pre-built definitions for all
Ubiquiti hardware in the Eirdom fleet.

Run the import tool on the server:

```bash
# Install the import tool
pip3 install netbox-device-type-library-import --break-system-packages

# Run import — filter to Ubiquiti only for initial import
cd /tmp
git clone https://github.com/netbox-community/devicetype-library.git
cd devicetype-library

# Export your NetBox API token first
export NETBOX_URL=https://netbox.eirdom.homes
export NETBOX_TOKEN=<your-api-token>

# Import Ubiquiti device types only
python3 -m netbox_device_type_library_import \
  --url ${NETBOX_URL} \
  --token ${NETBOX_TOKEN} \
  --vendors Ubiquiti
```

> Generate an API token in NetBox: Profile → API Tokens → Add

After importing Ubiquiti, import any other vendors in the fleet:

```bash
python3 -m netbox_device_type_library_import \
  --url ${NETBOX_URL} \
  --token ${NETBOX_TOKEN} \
  --vendors "Hewlett Packard Enterprise,Intel,Seagate"
```

### Step 3 — Configure UniFi Sync Plugin

1. In NetBox admin → **Plugins → UniFi Sync → Controllers → Add**
2. Configure:
   - Name: `Eirdom UDM-Pro-Max`
   - URL: `https://10.1.1.1`
   - Username: `netbox-sync` (the read-only account from Phase 1)
   - Password: read-only account password
   - Site: `Eirdom`
   - Verify SSL: Disabled (UDM uses self-signed cert on LAN)
3. Save

### Step 4 — Run First Sync (Dry Run)

Always run a dry run first before writing any data to NetBox:

```bash
docker exec netbox /opt/netbox/venv/bin/python \
  /opt/netbox/netbox/manage.py netbox_unifi_sync_run --dry-run --json
```

Review the output — it shows exactly what would be created or
updated. Verify the device names and IP addresses look correct before
proceeding.

### Step 5 — Run Live Sync

```bash
docker exec netbox /opt/netbox/venv/bin/python \
  /opt/netbox/netbox/manage.py netbox_unifi_sync_run
```

After the sync completes, navigate to **Devices → Devices** in NetBox.
All UniFi devices (switches, APs, UDM) should appear with their
management IPs, VLANs, and interfaces.

### Step 6 — Configure Scheduled Sync

The plugin supports NetBox's built-in scheduled jobs for automatic
recurring sync.

1. In NetBox admin → **Plugins → UniFi Sync → Sync Dashboard**
2. Click **Schedule Sync**
3. Set interval: every 60 minutes (adjust based on how dynamic
   your network changes are)
4. Save

The netbox-worker container handles the scheduled job execution.

---

## Phase 4 — LDAP Authentication

### Step 1 — Verify AD groups exist

Confirm the three groups from Phase 1 Step 2 exist in AD:
- `NetBox-Users`
- `NetBox-Staff`
- `NetBox-Admins`

Add your AD account to `NetBox-Admins`.

### Step 2 — Test LDAP login

1. Open a private browser window
2. Navigate to `https://netbox.eirdom.homes`
3. Log in with your AD credentials (just your username, not
   `username@ad.eirdom.homes`)
4. You should be logged in with superuser access

### Step 3 — Remove local superuser (optional)

Once LDAP login is confirmed working, the local superuser created
in Phase 2 can be deleted or disabled:

```bash
docker exec -it netbox /opt/netbox/venv/bin/python \
  /opt/netbox/netbox/manage.py shell -c \
  "from django.contrib.auth import get_user_model; \
   User = get_user_model(); \
   User.objects.filter(username='admin').delete()"
```

---

## Populating NetBox — Recommended Order

After the UniFi sync has run, manually complete the NetBox inventory
in this order for the best results:

1. **Racks** — add the server room rack under `Eirdom` site
2. **Manufacturers** — verify Ubiquiti, Intel, etc. exist (imported
   from device type library)
3. **Device Types** — verify USW-Pro-Max-48-PoE, U7 Pro, cameras etc.
   are imported
4. **Devices** — UniFi devices created by sync; manually add servers:
   - EIRDOM-PVE-01 (Proxmox host)
   - EIRDOM-DOCKER-01 (Docker host)
5. **IP Addresses** — VLANs and DHCP scopes synced from UniFi;
   manually add static IPs for servers
6. **Cables** — document physical cable runs between switches and
   devices (optional but valuable)
7. **VMs** — add virtual machines under EIRDOM-PVE-01

---

## Ongoing Management

### Viewing sync status

```bash
# Check last sync results
docker exec netbox /opt/netbox/venv/bin/python \
  /opt/netbox/netbox/manage.py netbox_unifi_sync_run --dry-run

# View sync logs in NetBox UI
# Navigate to: Plugins → UniFi Sync → Sync Dashboard
```

### Updating NetBox

```bash
sudo bash scripts/update.sh netbox
```

This rebuilds the custom image with the new NetBox base version
and restarts all containers. Back up the PostgreSQL database first:

```bash
docker exec netbox-postgres pg_dump \
  -U ${NETBOX_DB_USER} ${NETBOX_DB_NAME} > \
  ${BACKUP_PATH}/netbox-pre-upgrade-$(date +%Y%m%d).sql
```

### Viewing logs

```bash
# All containers
cd docker/netbox && docker compose logs -f

# Specific container
docker logs netbox -f
docker logs netbox-worker -f
```

---

## Troubleshooting

### Plugin sync jobs not running

The worker container must use the same image as the main netbox
container. If the worker was started before the image was built:

```bash
docker compose down
docker compose build
docker compose up -d
```

### LDAP login fails

```bash
# Test LDAP connectivity from inside the container
docker exec netbox python3 -c "
import ldap
conn = ldap.initialize('ldap://10.1.10.10')
conn.simple_bind_s('CN=netbox-svc,OU=Service Accounts,OU=Eirdom,DC=ad,DC=eirdom,DC=homes', 'YOUR_PASSWORD')
print('LDAP connection successful')
"
```

Common issues:
- VLAN 50 → VLAN 10 firewall rule needs TCP 389 open for LDAP
  (check `lan-rules.md` — Docker → Corporate DNS rule only covers
  port 53, LDAP on 389 needs its own rule)
- Service account password incorrect
- Group DN path doesn't match actual AD OU structure

### UniFi sync returns SSL errors

The UDM-Pro-Max uses a self-signed certificate on the LAN. The
plugin's `Verify SSL` setting must be **disabled** for the Eirdom
controller. Never disable SSL verification for controllers outside
your network.

### Device types not matching after sync

If UniFi device models don't match imported device types, the sync
creates the devices without a device type. Fix by:
1. Verifying the device type exists in NetBox (check manufacturer
   spelling — must be exactly `Ubiquiti`)
2. Manually assigning the device type in the device edit view
3. Running sync again — it will update the device type if it finds
   a match

---

## DNS Record

Add to internal DNS on EIRDOM-DC-01:

```
netbox.eirdom.homes    A    10.1.50.10
```

---

## Related Documentation

- [`services.md`](../../docs/services.md) — Service reference
- [`vlans.md`](../../docs/vlans.md) — VLAN and IP reference
- [`lan-rules.md`](../../unifi/firewall/lan-rules.md) — Firewall rules
  (note: LDAP port 389 from DOCKER → CORPORATE needs adding)
- [`decisions.md`](../../docs/decisions.md) — Architecture decisions