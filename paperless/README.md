# Paperless-ngx
> Document Management — Scan, OCR, Tag, Search
> Part of the Eirdom infrastructure

---

## Overview

Paperless-ngx is the home document archive. Physical documents —
warranties, inspection reports, insurance policies, permits, receipts,
tax documents — are scanned or dropped into a consume folder and
Paperless automatically OCRs them, makes them text-searchable, and
indexes them with smart tags.

**Authentication:** Authentik ForwardAuth with header passthrough.
After Authentik authenticates you, your username is passed via the
`X-Authentik-Username` header and Paperless automatically logs you
in as the correct user — no separate Paperless login required.

---

## Repository Structure

```
docker/paperless/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Fill in .env

```bash
cd docker/paperless
cp .env.example .env
nano .env
```

| Variable | How to Generate |
|----------|----------------|
| `PAPERLESS_DB_PASSWORD` | `openssl rand -base64 32` |
| `PAPERLESS_SECRET_KEY` | `openssl rand -base64 50` |
| `PAPERLESS_ADMIN_PASSWORD` | Strong password → password manager |

### Step 2 — Start the stack

```bash
docker compose up -d
docker compose logs -f paperless
# Wait for: "Startup successful"
```

First start takes 1–2 minutes while the database schema is created.

### Step 3 — First login

Navigate to `https://paperless.eirdom.homes`. Authentik will
authenticate you and pass your username — Paperless will
automatically log you in.

Verify the admin account exists under **Settings → Users & Groups**.

### Step 4 — Remove initial admin credentials

The `PAPERLESS_ADMIN_USER` and `PAPERLESS_ADMIN_PASSWORD` values
in `.env` are only used on the very first container start to create
the superuser. Leave them in place until you have verified first
login works, then remove them:

```bash
# Edit docker/paperless/.env
# Remove or blank these two lines:
# PAPERLESS_ADMIN_USER=
# PAPERLESS_ADMIN_PASSWORD=

docker compose up -d  # restart to apply
```

> If you leave them in, they are not a security risk (the admin
> account already exists and won't be recreated), but it's clean
> practice to remove bootstrap credentials.

---

## Document Inbox (Consume Folder)

The consume folder is watched continuously. Any file dropped into it
is automatically ingested, OCR'd, and indexed.

**Consume folder path on the host:**
```
${MEDIA_PATH}/paperless/consume/
# Default: /media/arr/paperless/consume/
```

### Ways to get documents into the consume folder

**From a network scanner:**
Configure the scanner to save directly to `\\EIRDOM-DOCKER-01\paperless\consume`
(set up a Samba share if needed) or via FTP/SFTP.

**From a phone (iOS):**
Use the Files app → Connect to Server → `smb://10.1.50.10` → navigate
to the consume folder. Or use a scanning app (e.g. Adobe Scan,
Microsoft Lens) and save directly to the network path.

**From a Windows workstation:**
Map a network drive to `\\10.1.50.10\paperless\consume` or copy
files directly via the Files app.

**From Stirling PDF:**
After processing a document in Stirling PDF, download and drop it
into the consume folder.

---

## Tags, Correspondents, and Document Types

Paperless can automatically assign tags based on document content.
After a few weeks of use, set up automatic classification rules:

**Settings → Workflows** — create rules like:
- If content contains "warranty" → tag: Warranty
- If content contains "insurance" → correspondent: Insurance Co
- If content contains "invoice" → document type: Invoice

The more you use it, the smarter the auto-classification becomes
as Paperless learns from your manual assignments.

---

## Storage Layout

```
${DOCKER_DATA_PATH}/paperless/
├── db/           PostgreSQL database files
├── data/         Application data (index, thumbnails, logs)
└── media/        Processed document files (PDFs with OCR layer)

${MEDIA_PATH}/paperless/
├── consume/      Drop documents here for automatic ingestion
└── export/       Paperless export destination (for full backup export)
```

---

## Backup

`scripts/backup.sh` runs daily and captures:

- **PostgreSQL dump** (`paperless-db.sql.gz`) — all document metadata,
  tags, correspondents, and search index
- **Data directory** (`paperless-data.tar.gz`) — thumbnails, index files
- **Media directory** (`paperless-media.tar.gz`) — the actual document
  files (PDFs with embedded OCR text layer)

> The media directory backup is the most important — it contains the
> actual documents. The DB backup contains all the metadata.
> Restoring both together gives you a complete recovery.

---

## Troubleshooting

### Document stuck in "Processing" or "Inbox"

Check the container logs for OCR errors:

```bash
docker logs paperless --tail 50
```

Common causes:
- Corrupted PDF — try running through Stirling PDF → Repair first
- Very large file — OCR of 100+ page documents takes time, be patient
- Unsupported file type — Paperless supports PDF, PNG, JPG, TIFF, TXT

### Authentik auto-login not working

Verify the `PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME` is set to
`HTTP_X_AUTHENTIK_USERNAME` in `docker-compose.yml` and that
Authentik is passing the username header. Check in Authentik admin →
Applications → Providers → (Paperless provider) → check that
`X-authentik-username` is in the response headers list.

### Can't reach consume folder from Windows

Ensure the Docker host has Samba installed if you're using SMB file
sharing. Alternatively, use SCP/SFTP via `10.1.50.10` with your
domain credentials (if SSSD is configured on the Docker host).

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Paperless service entry
- [`docs/deployment-guide.md`](../../docs/deployment-guide.md) — Phase 15 setup
- [`docker/stirling-pdf/README.md`](../stirling-pdf/README.md) — PDF processing (pairs well)
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-034