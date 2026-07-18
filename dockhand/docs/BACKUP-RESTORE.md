# Dockhand Backup and Restore

## What must be backed up

Back up the complete persistent directory:

```text
/opt/eirdom/appdata/dockhand
```

Dockhand's SQLite database is stored beneath the data directory, normally at:

```text
data/db/dockhand.db
```

The database contains configuration that filesystem-only stack backups do not,
including encrypted Dockhand-managed secrets. The Eirdom Docker Git repository
must also be backed up independently.

## Consistent backup

```bash
cd ~/eirdom/docker/dockhand
docker compose --env-file ../../.env --env-file .env stop dockhand

sudo tar -C /opt/eirdom/appdata \
  -czf /opt/eirdom/backups/dockhand-$(date +%F-%H%M%S).tar.gz \
  dockhand

docker compose --env-file ../../.env --env-file .env start dockhand
```

For online backups, use Dockhand's built-in database backup tooling or a SQLite
backup operation rather than copying an actively written database blindly.

## Restore

```bash
cd ~/eirdom/docker/dockhand
docker compose --env-file ../../.env --env-file .env down

sudo mv /opt/eirdom/appdata/dockhand \
  /opt/eirdom/appdata/dockhand.pre-restore.$(date +%s)

sudo mkdir -p /opt/eirdom/appdata
sudo tar -C /opt/eirdom/appdata -xzf /path/to/dockhand-backup.tar.gz
sudo chown -R "$(id -u):$(id -g)" /opt/eirdom/appdata/dockhand

docker compose --env-file ../../.env --env-file .env up -d
```

Validate authentication, environments, Git integrations, registries, schedules,
and any stored secrets after restoration.
