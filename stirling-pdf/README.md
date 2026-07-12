# Stirling PDF
> Local PDF Processing — No Data Leaves the Network
> Part of the Eirdom infrastructure

---

## Overview

Stirling PDF is a local PDF Swiss Army knife. It replaces every online
PDF tool — SmallPDF, iLovePDF, Adobe online, and similar — for all
PDF work done on the home network.

All processing happens in-memory inside the container. No files are
stored between sessions. No data is sent to any external service.

**Available operations:**

- Merge multiple PDFs into one
- Split a PDF by page range or every N pages
- Compress — reduce file size for emailing
- Rotate, reorder, delete pages
- Convert PDF → Word, Excel, PowerPoint, HTML
- Convert Word, Excel, images → PDF
- OCR — make scanned PDFs text-searchable
- Add watermarks, page numbers, headers/footers
- Redact — permanently remove sensitive text or areas
- Repair corrupted PDFs
- Compare two PDFs side by side

---

## Repository Structure

```
docker/stirling-pdf/
├── docker-compose.yml
└── .env.example
```

---

## Setup

No secrets or credentials required. Stirling PDF is fully stateless.

```bash
cd docker/stirling-pdf
docker compose up -d
```

Navigate to `https://pdf.eirdom.homes`. Authentik SSO handles
authentication — no separate Stirling PDF login is needed.

That's it. No further configuration required.

---

## Configuration

All configuration is handled via environment variables in
`docker-compose.yml`. Current settings:

| Variable | Value | Notes |
|----------|-------|-------|
| `SECURITY_ENABLE_LOGIN` | `false` | Authentik handles auth |
| `SYSTEM_MAXFILESIZE` | `100` | 100MB max upload — covers large architectural PDFs |
| `UI_APP_NAME` | `Eirdom PDF` | Branding in the UI |
| `SYSTEM_DEFAULTLOCALE` | `en-US` | Interface language |

### OCR Language Support

English is supported out of the box. To add additional languages
(e.g. for foreign-language documents), uncomment the tessdata volume
mount in `docker-compose.yml` and download the language pack:

```bash
# Example: add Spanish
docker exec stirling-pdf apt-get install -y tesseract-ocr-spa
```

---

## Storage

Stirling PDF is completely stateless — no user data is stored between
sessions. The config directory (`${DOCKER_DATA_PATH}/stirling-pdf/configs`)
stores only application settings, not documents. The logs directory
stores access logs.

`scripts/backup.sh` backs up the config directory weekly. There is
nothing to restore in a disaster recovery scenario — simply start the
container and it is immediately ready.

---

## Practical Uses

Given you're in a new home build, common use cases:

- **Warranty documents** — merge multiple warranty PDFs into a single
  organised file before adding to Paperless
- **Contractor quotes** — compress large quote PDFs before emailing
- **Plans and permits** — OCR scanned documents so they're searchable
  in Paperless
- **Sensitive documents** — redact account numbers or personal
  information before sharing
- **Tax documents** — merge all W-2s, 1099s, and receipts into one
  annual file

---

## Troubleshooting

### Large file upload fails

The default max upload size is set to 100MB in `docker-compose.yml`
via `SYSTEM_MAXFILESIZE`. If you need larger (e.g. full architectural
drawing sets), increase this value:

```yaml
SYSTEM_MAXFILESIZE: "200"
```

Restart the container after changing: `docker compose up -d`

### OCR produces garbled text

The document may be a low-resolution scan. Try increasing DPI in the
OCR settings. For very poor quality scans, results will be limited
regardless of settings — this is a source document quality issue.

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Stirling PDF service entry
- [`docs/deployment-guide.md`](../../docs/deployment-guide.md) — Phase 15 setup
- [`docker/paperless/README.md`](../paperless/README.md) — Document management (pairs well)