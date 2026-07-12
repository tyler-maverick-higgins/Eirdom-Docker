# Homebox
> Home Asset Inventory — Appliances, Tools, Warranties
> Part of the Eirdom infrastructure

---

## Overview

Homebox is the home asset register. Every appliance, tool, piece of
infrastructure hardware, and significant purchase is tracked here with
purchase dates, serial numbers, warranty expiry, and linked documents.

**Why start from day one:**
A new construction home means dozens of new appliances all arriving
at once — refrigerator, dishwasher, HVAC, water heater, washers,
smart devices, and all the Eirdom network and server hardware. Tracking
them from the moment they're delivered takes minutes per item. Trying
to reconstruct this information a year later when something breaks
and you need a warranty is significantly harder.

**Pairs with Paperless-ngx** — link warranty documents stored in
Paperless directly to items in Homebox.

---

## Repository Structure

```
docker/homebox/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Start the container

No `.env` values required beyond root `.env`.

```bash
cd docker/homebox
docker compose up -d
```

### Step 2 — Create admin account

Navigate to `https://homebox.eirdom.homes`.

The first account registered becomes the permanent admin. Create
your account before sharing the URL with family. Set a strong
password and save to password manager.

### Step 3 — Create locations

Set up your home's physical locations before adding items:

Manage → Locations → Create:

| Location | Sub-Locations |
|----------|--------------|
| Kitchen | — |
| Laundry Room | — |
| Garage | Server Room |
| Master Bedroom | — |
| Living Room | — |
| Utility | HVAC, Water Heater |
| Outdoors | — |

### Step 4 — Create labels

Labels are searchable tags. Suggested starting set:

- `warranty-active`
- `warranty-expired`
- `eirdom-infrastructure` (all network/server hardware)
- `appliance`
- `tool`
- `smart-home`

### Step 5 — Start adding items

Priority items to add first — the ones where warranty or serial
number matters most:

**Eirdom Infrastructure:**
- UDM-Pro-Max, USW switches, U7 Pro APs
- EIRDOM-PVE-01, EIRDOM-DOCKER-01 (server hardware)
- All cameras (G5 Pro, G6 Instant 180, AI Theta, G5 Dome)
- UNVR-Pro

**Kitchen Appliances:**
- Refrigerator, range, dishwasher, microwave, vent hood, wine center

**Laundry:**
- Washer, dryer

**HVAC & Mechanical:**
- Furnace, water heater (tankless gas), ERV unit

---

## Item Fields

For each item, fill in what you have:

| Field | Notes |
|-------|-------|
| Name | Descriptive — "Café 36\" Range CES7002P2" |
| Serial Number | Found on label or in documentation |
| Model | Model number from packaging |
| Purchase Date | Date of delivery or purchase |
| Purchase Price | Useful for insurance purposes |
| Warranty Expiry | Calculate from purchase date + warranty period |
| Location | Where the item physically lives |
| Labels | `appliance`, `warranty-active` etc. |
| Notes | Anything useful — filter size, service dates, etc. |
| Attachments | Link or upload warranty documents from Paperless |

---

## Maintenance Tracking

Homebox supports maintenance records per item — useful for:

- HVAC filter replacement (every 90 days)
- Furnace service (annually)
- Water heater flush (annually)
- Garage door spring inspection
- Roof inspection

Add maintenance tasks under an item → Maintenance → Add Maintenance.
Set a scheduled date and Homebox tracks it.

---

## Storage

All data in a single SQLite database at `${DOCKER_DATA_PATH}/homebox/`.
Backed up daily by `scripts/backup.sh`.

---

## Troubleshooting

### Images not uploading

The `HBOX_WEB_MAX_UPLOAD_SIZE` is set to 10MB. If you're uploading
high-res photos of items, compress them first or increase this value
in `docker-compose.yml` and restart.

### Items not appearing after search

Homebox search is case-insensitive but matches on name, description,
and serial number. If an item isn't appearing, check you're searching
the right field — serial numbers are not included in the default
search view.

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Homebox service entry
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-037
- [`docker/paperless/README.md`](../paperless/README.md) — Warranty document storage