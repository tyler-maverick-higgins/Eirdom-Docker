# Actual Budget
> Local-First Personal Finance & Budgeting
> Part of the Eirdom infrastructure

---

## Overview

Actual Budget is a zero-based budgeting tool — every dollar of income
is assigned to a category before it's spent. It runs entirely locally
with no cloud sync. Bank account details never leave the network.

**Why `chain-public` instead of Authentik SSO:**
Financial data warrants explicit login every time. Unlike other
services where Authentik auto-login via header passthrough is a
convenience, budget data is sensitive enough that each session
should require deliberate authentication. `chain-public` means
Authentik protects the URL from the internet but does not auto-login
— Actual's own server password is required.

---

## Repository Structure

```
docker/actual/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Start the container

No `.env` values required beyond root `.env`.

```bash
cd docker/actual
docker compose up -d
```

### Step 2 — Set server password

Navigate to `https://actual.eirdom.homes`.

On first access you are prompted to create a server password.
This password is required once per new device or browser. Set a
strong password and save to password manager.

> This is a **server** password — not a per-user login. Anyone with
> this password can access the budget files on the server. Keep it
> secure and share it only with whoever should have budget access.

### Step 3 — Create a budget file

Click **Create new file** → give it a name (e.g. "Eirdom Budget").

Actual creates a local budget file on the server. You can create
multiple budget files — one for the household budget, one for the
home build project, etc.

### Step 4 — Connect desktop and mobile apps

Download the Actual Budget app:

| Platform | Source |
|----------|--------|
| Windows / macOS / Linux | [actualbudget.org](https://actualbudget.org/docs/install/desktop) |
| iOS | App Store — search "Actual Budget" |
| Android | App Store — search "Actual Budget" |

In the app: Add server → `https://actual.eirdom.homes` → enter
server password → select your budget file.

All devices sync to the same budget file on the server — changes
on one device appear on all others.

---

## Zero-Based Budgeting Basics

Actual uses zero-based budgeting — every dollar of income is
assigned to a category. The goal is Income − Budgeted = $0.

**Monthly workflow:**

1. At the start of the month, budget all expected income to categories
2. As transactions come in, categorise them
3. If a category runs over, move money from another category
4. Review at month end — adjust next month's budget accordingly

**Getting started:**

1. Add your accounts (checking, savings, credit cards)
2. Enter current balances as opening transactions
3. Create budget categories that reflect your actual spending
4. Budget this month's income

---

## Suggested Budget Categories

Given the Eirdom context — new home, family with kids — a starting
framework:

**Housing:**
- Mortgage
- HOA Fees
- Property Tax (if escrowed separately)
- Home Insurance

**Home Maintenance:**
- HVAC Service
- Landscaping
- Repairs & Maintenance
- Eirdom Infrastructure (server/network upgrades)

**Utilities:**
- Electric
- Gas
- Water
- Internet

**Groceries & Household:**
- Groceries
- Household Supplies
- Personal Care

**Family:**
- Children's Activities
- Clothing
- Medical / Dental

**Transportation:**
- Fuel
- Car Payment
- Car Insurance
- Registration

**Savings:**
- Emergency Fund
- Home Improvement Fund
- Vacation

---

## Importing Transactions

Actual does not connect directly to banks (by design — no bank
credentials leave the device). Transactions are imported via CSV:

1. Download a CSV transaction export from your bank's website
2. Actual → Account → Import → select the CSV
3. Actual maps columns automatically for most bank formats
4. Review and categorise the imported transactions

Do this monthly — it takes about 10 minutes once you're set up.

---

## Storage

All budget data in `${DOCKER_DATA_PATH}/actual/`. This is a
directory of SQLite files — one per budget file. Backed up daily
by `scripts/backup.sh`.

> The backup includes all budget files and transaction history.
> Restoring from backup fully recovers all data including history.

---

## Troubleshooting

### "Invalid password" on new device

The server password is set once and stored in the server's config.
If you've forgotten it, reset it by stopping the container, deleting
`${DOCKER_DATA_PATH}/actual/server-files/account.sqlite`, and
restarting. You'll be prompted to set a new password. **Budget files
are not affected** — only the server auth is reset.

### Sync not working between devices

All devices must be pointing to the same server URL
(`https://actual.eirdom.homes`) and using the same server password.
If a device shows "out of sync", close and reopen the budget file to
force a full sync.

### CSV import not matching columns

Different banks format CSVs differently. Actual's column mapper
handles most formats but occasionally needs manual adjustment.
Common issue: date format mismatch. Set the date format to match
your bank's export (MM/DD/YYYY vs DD/MM/YYYY vs YYYY-MM-DD).

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Actual Budget service entry
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-040