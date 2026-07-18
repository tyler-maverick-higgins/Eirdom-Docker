# Dockhand — Eirdom Deployment

Dockhand provides Docker container management, Compose project orchestration,
Git integration, image update visibility, vulnerability scanning, and
multi-environment support.

This deployment is designed for `eirdom-docker-01` and follows the Eirdom
standards:

- version-pinned image;
- no direct host port exposure;
- Traefik HTTPS routing;
- persistent data under `/opt/eirdom/appdata`;
- access to the existing Eirdom Docker repository using matching paths;
- non-root runtime identity with Docker socket group access;
- Git as the authoritative source of truth.

## Security boundary

Dockhand has access to `/var/run/docker.sock`. Docker socket access is
functionally equivalent to administrative/root control of the Docker host.
Treat Dockhand as a Tier-0 administrative service:

- do not publish it through Cloudflare Tunnel;
- permit access only from trusted LAN/VPN networks;
- enable Dockhand authentication immediately;
- configure Authentik OIDC after initial setup;
- keep at least one break-glass local administrator until OIDC is validated;
- back up Dockhand's database and data directory;
- review activity after every image or stack operation.

## Files

```text
dockhand/
├── docker-compose.yml
├── .env.example
├── README.md
└── docs/
    ├── AUTHENTIK-OIDC.md
    ├── BACKUP-RESTORE.md
    └── UPDATE-RUNBOOK.md
```

## Prerequisites

1. Docker and Docker Compose are working.
2. The external `proxy` network exists.
3. Traefik is running and can resolve `chain-public@file`.
4. Internal DNS resolves `dockhand.eirdom.homes` to Traefik.
5. CPU cooling and existing unhealthy services have been remediated before
   adding another privileged workload.

Verify the Docker socket group ID:

```bash
stat -c '%g' /var/run/docker.sock
```

Verify your IDs:

```bash
id -u
id -g
```

## Installation

From the Eirdom-Docker repository:

```bash
cd ~/eirdom/docker/dockhand
cp .env.example .env
nano .env
```

Create persistent storage:

```bash
sudo mkdir -p /opt/eirdom/appdata/dockhand
sudo chown -R "$(id -u):$(id -g)" /opt/eirdom/appdata/dockhand
sudo chmod 750 /opt/eirdom/appdata/dockhand
```

Validate the rendered Compose file:

```bash
docker compose --env-file ../../.env --env-file .env config
```

Deploy:

```bash
docker compose --env-file ../../.env --env-file .env up -d
```

Or through the Eirdom Makefile:

```bash
cd ~/eirdom/docker
make up SVC=dockhand
```

## Validation

```bash
docker ps --filter name=dockhand
docker logs dockhand --tail 100
docker exec dockhand id
docker exec dockhand test -S /var/run/docker.sock
curl -ksS https://dockhand.eirdom.homes/api/health | jq
```

Traefik should report the backend as healthy, and the UI should load at:

```text
https://dockhand.eirdom.homes
```

## First-time configuration

Authentication is disabled on first launch. Complete this before using Dockhand
for operations:

1. Open **Settings → Authentication**.
2. Enable authentication.
3. Create a local break-glass administrator.
4. Sign out and verify the account works.
5. Configure Authentik OIDC using `docs/AUTHENTIK-OIDC.md`.
6. Keep local login enabled until OIDC has been tested through a fresh browser
   session.

## Adopting existing Compose projects

Dockhand sees the Eirdom Compose repository at the same absolute path inside and
outside the container:

```text
/home/dockeradm/eirdom/docker
```

Use **Stacks → Import**, browse to that path, and scan for Compose files. Import
one project at a time and verify its rendered `.env` files before permitting
Dockhand to deploy it.

Do not make uncommitted production edits only in Dockhand. After any UI edit:

```bash
cd ~/eirdom/docker
git status
git diff
```

Review, test, and commit the change through the normal Eirdom process.

## Version pinning

The image is pinned in `.env`:

```text
DOCKHAND_IMAGE=fnsys/dockhand:v1.0.37
```

Do not change it to `latest`. Follow `docs/UPDATE-RUNBOOK.md` for upgrades.

## Metrics

Set:

```text
DOCKHAND_EXPORT_METRICS=true
```

Dockhand then exposes `/metrics`. When authentication is enabled, configure
Prometheus with a Dockhand API bearer token. Do not expose metrics publicly.
