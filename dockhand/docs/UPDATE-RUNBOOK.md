# Dockhand Update Runbook

Dockhand is an administrative control plane. Updates must be tested and
reversible.

## 1. Pre-change checks

```bash
cd ~/eirdom/docker/dockhand
docker compose --env-file ../../.env --env-file .env config >/tmp/dockhand-rendered.yml
docker inspect dockhand --format '{{.Config.Image}}'
docker logs dockhand --tail 100
curl -ksS https://dockhand.eirdom.homes/api/health | jq
```

Confirm:

- no active deployments, scans, backups, or image pulls;
- authentication works;
- the Docker host is thermally stable;
- the current Dockhand data backup is recent;
- the target release notes and breaking changes have been reviewed.

## 2. Backup

Follow `BACKUP-RESTORE.md` and commit the current repository state.

```bash
git checkout -b update/dockhand-vX.Y.Z
git add dockhand
git commit -m "chore(dockhand): snapshot before vX.Y.Z update"
```

## 3. Update the version pin

Edit only the pin in `.env` or the central image inventory:

```text
DOCKHAND_IMAGE=fnsys/dockhand:vX.Y.Z
```

Never use `latest` in production.

## 4. Pull and recreate

```bash
docker compose --env-file ../../.env --env-file .env pull dockhand
docker compose --env-file ../../.env --env-file .env up -d --force-recreate dockhand
```

## 5. Validation

```bash
docker ps --filter name=dockhand
docker logs dockhand --tail 200
curl -ksS https://dockhand.eirdom.homes/api/health | jq
```

Validate in the UI:

- local and OIDC login;
- environment connection;
- container inventory;
- Compose project discovery;
- logs and terminal;
- image update checks;
- vulnerability scanner;
- scheduled tasks;
- Git repository access;
- no unexpected stack modifications.

Observe for at least 24 hours before merging the update branch.

## 6. Rollback

Set `DOCKHAND_IMAGE` back to the previous version, then:

```bash
docker compose --env-file ../../.env --env-file .env pull dockhand
docker compose --env-file ../../.env --env-file .env up -d --force-recreate dockhand
```

If the newer version migrated the database incompatibly, stop Dockhand and
restore the pre-update data backup before starting the old image.
