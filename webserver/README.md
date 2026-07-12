# Webserver Stack
> WordPress · MariaDB · Adminer
> Part of the Eirdom infrastructure

---

## Overview

This stack runs the Eirdom family website at `https://eirdom.homes`.
It includes:

- **WordPress** — family website CMS
- **MariaDB** — WordPress database (isolated, not reachable externally)
- **Adminer** — lightweight database management UI (internal only)

All traffic routes through Traefik. No ports are exposed directly
to any network interface. Adminer is restricted to VLAN 10 only
and is never exposed externally through Cloudflare.

---

## Directory Structure

```
docker/webserver/
├── docker-compose.yml
├── .env.example
└── README.md
```

WordPress files are stored at `${DOCKER_DATA_PATH}/wordpress/html`
and the database at `${DOCKER_DATA_PATH}/wordpress/db` on the server.

---

## First-Time Setup

Follow these steps in order. Do not start the stack until all steps
are completed.

---

### Step 1 — Fill in the .env file

```bash
cd docker/webserver
cp .env.example .env
nano .env
```

Fill in every value. Pay particular attention to:

- Use a different password for `WP_DB_ROOT_PASSWORD` and
  `WP_DB_PASSWORD` — never reuse these
- Change `WP_TABLE_PREFIX` from the default `wp_` — using a custom
  prefix (e.g. `eirdom_`) protects against automated SQL injection
  attacks that target the default prefix
- Do not use `admin` as `WP_ADMIN_USER` — it is the first username
  attackers try in brute force attacks
- Store all passwords in your password manager before saving the file

---

### Step 2 — Create the data directories

If `provision.sh` has already been run these will exist. If not,
create them manually:

```bash
mkdir -p ${DOCKER_DATA_PATH}/wordpress/html
mkdir -p ${DOCKER_DATA_PATH}/wordpress/db
chown -R 1000:1000 ${DOCKER_DATA_PATH}/wordpress
```

---

### Step 3 — Add the internal DNS record

On EIRDOM-DC-01, add an A record in the `eirdom.homes` forward
lookup zone:

```
eirdom.homes   →   10.1.50.10
www            →   CNAME → eirdom.homes
adminer        →   A → 10.1.50.10
```

See `docs/vlans.md` — Internal DNS Records section.

---

### Step 4 — Start the stack

Always start Traefik first if it is not already running:

```bash
cd docker/traefik && docker compose up -d
cd docker/webserver && docker compose up -d
```

Watch the logs to confirm all three containers start cleanly:

```bash
docker compose logs -f
```

MariaDB will initialize the database on first start — this takes
30–60 seconds. WordPress will wait for MariaDB to be healthy
before starting (healthcheck is configured). You will see
`mariadb | ready for connections` in the logs before WordPress
starts.

---

### Step 5 — Complete the WordPress installation

Open a browser and navigate to `https://eirdom.homes`.

WordPress will present the installation wizard:

1. Select language
2. Enter your site title (e.g. "Eirdom")
3. Enter the admin username from your `.env` file
4. Enter the admin password from your `.env` file
5. Enter the admin email from your `.env` file
6. Click **Install WordPress**

> If you see a database connection error, check that MariaDB is
> healthy: `docker compose ps` — MariaDB should show `healthy`.

---

### Step 6 — Configure SMTP (WP Mail SMTP plugin)

WordPress needs SMTP to send registration emails, password resets,
and event notifications.

1. In the WordPress admin, go to **Plugins → Add New**
2. Search for **WP Mail SMTP** and install it
3. Go to **WP Mail SMTP → Settings**
4. Configure:
   - **From Email:** value from `SMTP_FROM_EMAIL` in your `.env`
   - **From Name:** `Eirdom Family`
   - **Mailer:** Other SMTP
   - **SMTP Host:** `smtp.gmail.com`
   - **Encryption:** TLS
   - **SMTP Port:** `587`
   - **Authentication:** On
   - **Username:** your Gmail address
   - **Password:** your Gmail App Password (from `.env`)
5. Click **Save Settings**
6. Use the **Email Test** tab to send a test email and confirm it works

> If the test email fails, double-check that 2FA is enabled on the
> Gmail account and that you used an App Password (not your regular
> Gmail password).

---

### Step 7 — Install recommended plugins

Install the following plugins from **Plugins → Add New**:

| Plugin | Purpose |
|--------|---------|
| **Members** | Granular content access control — restrict pages and posts by user role or individual user |
| **The Events Calendar** | Family calendar for events and important dates |
| **FileBird** | Organize the WordPress media library into folders for photos, videos, documents |
| **WP File Manager** | Upload and manage documents directly from the admin area |
| **Smush** | Automatic image optimization — compresses uploaded photos without visible quality loss |
| **UpdraftPlus** | Additional backup layer — configure to back up to a remote destination |
| **Wordfence** | WordPress-specific firewall and malware scanner |
| **WP Mail SMTP** | SMTP configuration (installed in Step 6) |

> Install plugins one at a time and test after each installation.
> Do not install all plugins simultaneously — if something breaks
> it is harder to identify the cause.

---

### Step 8 — Configure user registration

WordPress member registration for family and friends:

1. Go to **Settings → General**
2. Check **Anyone can register**
3. Set **New User Default Role** to **Subscriber**
4. Install the **Members** plugin (Step 7)
5. Use Members to create custom roles (e.g. `Family`, `Friends`)
   with different content access levels
6. After a new user registers, manually promote them from Subscriber
   to the appropriate role in **Users → All Users**

> Keep **New User Default Role** as Subscriber — this means new
> registrations have no content access until you manually review
> and promote them. This prevents strangers who find the registration
> page from accessing family content.

---

## Accessing Adminer

Adminer is the database management UI. It is for advanced use only —
you should rarely need it in normal operation.

**URL:** `https://adminer.eirdom.homes`
**Access:** VLAN 10 only — must be on the trusted network
**Login:**
- System: MySQL
- Server: `mariadb`
- Username: value of `WP_DB_USER` from your `.env`
- Password: value of `WP_DB_PASSWORD` from your `.env`
- Database: value of `WP_DB_NAME` from your `.env`

> For destructive operations (database repair, table modifications)
> use the root credentials. For normal browsing use the WordPress
> user credentials.

> **Warning:** Never expose Adminer externally. The Traefik IP
> whitelist restricts it to VLAN 10 (`10.1.10.0/24`) only.
> If you cannot reach it, confirm you are connected to the
> `Eirdom` SSID or a wired VLAN 10 port.

---

## Ongoing Management

### Updating WordPress

WordPress core, theme, and plugin updates are managed from the
WordPress admin dashboard at `https://eirdom.homes/wp-admin`.

Go to **Dashboard → Updates** and apply available updates regularly.
Always run a backup before applying major updates.

### Updating the container images

Container image updates (WordPress, MariaDB, Adminer) are handled
by `scripts/update.sh`:

```bash
sudo bash scripts/update.sh webserver
```

This pulls the latest images, recreates containers, and runs health
checks. A backup runs automatically before the update.

### Backing up

The `scripts/backup.sh` script backs up both the WordPress files and
MariaDB database daily. Verify backups are running:

```bash
ls -lh ${BACKUP_PATH}/
```

To manually trigger a backup:

```bash
sudo bash scripts/backup.sh
```

### Viewing logs

```bash
# All containers
cd docker/webserver && docker compose logs -f

# Specific container
docker logs wordpress -f
docker logs mariadb -f
docker logs adminer -f
```

### Stopping and starting

```bash
# Stop the stack
cd docker/webserver && docker compose down

# Start the stack
cd docker/webserver && docker compose up -d

# Restart a single container
docker restart wordpress
```

---

## Troubleshooting

### WordPress shows "Error establishing a database connection"

MariaDB is not ready or the credentials are wrong.

```bash
# Check MariaDB status
docker compose ps

# Check MariaDB logs
docker logs mariadb --tail 50

# Verify credentials match between .env and WordPress
docker exec -it mariadb mysql -u${WP_DB_USER} -p${WP_DB_PASSWORD} ${WP_DB_NAME}
```

### WordPress is not reachable at eirdom.homes

Traefik routing issue or DNS not resolving.

```bash
# Check Traefik is running
docker ps | grep traefik

# Check Traefik logs for routing errors
docker logs traefik --tail 50

# Check DNS resolves correctly from inside the network
nslookup eirdom.homes 10.1.10.10
# Should return 10.1.50.10
```

### Adminer is not reachable

Confirm you are on VLAN 10. The IP whitelist middleware blocks all
other subnets.

```bash
# Verify your IP is in the 10.1.10.0/24 range
ip addr   # Linux
ipconfig  # Windows

# Check Traefik middleware is applied correctly
docker logs traefik --tail 50 | grep adminer
```

### Emails not sending

```bash
# Use the WP Mail SMTP test tool in wp-admin first
# If that fails, verify Gmail App Password is correct:
# Google Account → Security → App Passwords

# Check WordPress debug log if WP_DEBUG is temporarily enabled
docker exec wordpress tail -f /var/www/html/wp-content/debug.log
```

### MariaDB disk space growing large

WordPress media uploads and database growth are normal. Check sizes:

```bash
# Database size
docker exec mariadb du -sh /var/lib/mysql

# WordPress files size
du -sh ${DOCKER_DATA_PATH}/wordpress/html

# Run database optimization from Adminer:
# SELECT → wordpress database → Optimize all tables
```

---

## Storage Migration to UniFi NAS (Future)

When the UniFi NAS is available, migrate WordPress media storage
by updating the volume mount in `docker-compose.yml`:

```yaml
# Current
- ${DOCKER_DATA_PATH}/wordpress/html:/var/www/html

# Future — NAS mount via NFS
- /mnt/nas/wordpress/html:/var/www/html
```

Before migrating:
1. Stop the WordPress container
2. Copy the existing `html` directory to the NAS mount point
3. Update the compose file volume path
4. Start the container and verify
5. Confirm media loads correctly before removing the old data

The database (`/var/lib/mysql`) can remain on local storage — it is
small and benefits from fast local SSD I/O. Only the `html` directory
(which contains all uploaded media) needs to move to the NAS.

---

## Related Documentation

- [`services.md`](../../docs/services.md) — Full service reference including URLs
- [`network-diagram.md`](../../docs/network-diagram.md) — Network topology
- [`lan-rules.md`](../../unifi/firewall/lan-rules.md) — Firewall rules including Adminer IP restriction
- [`decisions.md`](../../docs/decisions.md) — Architecture decisions