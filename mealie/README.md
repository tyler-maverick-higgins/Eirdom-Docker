# Mealie
> Recipe Management · Meal Planning · Shopping Lists
> Part of the Eirdom infrastructure

---

## Overview

Mealie is the family recipe library and meal planner. Recipes live
in one place — not scattered across browser bookmarks, Pinterest
boards, and screenshot folders. Any recipe URL from the internet
can be imported with one click. Weekly meal plans generate shopping
lists automatically, and those lists can be pushed directly to Grocy.

---

## Repository Structure

```
docker/mealie/
├── docker-compose.yml
└── .env.example
```

---

## Setup

### Step 1 — Fill in .env

```bash
cd docker/mealie
cp .env.example .env
nano .env
```

| Variable | How to Generate |
|----------|----------------|
| `MEALIE_DB_PASSWORD` | `openssl rand -base64 32` |
| `MEALIE_ADMIN_PASSWORD` | Strong password → password manager |

### Step 2 — Start the stack

```bash
docker compose up -d
docker compose logs -f mealie
# Wait for: "Application startup complete"
```

### Step 3 — First login

Navigate to `https://mealie.eirdom.homes`.

Log in with the email and password set in `.env`
(`MEALIE_ADMIN_EMAIL` and `MEALIE_ADMIN_PASSWORD`).

### Step 4 — Invite family members

`ALLOW_SIGNUP` is set to `false` — family members cannot create
their own accounts. Invite them from the admin panel:

Admin → Manage Users → Create User:
- Fill in name and email
- Set a temporary password (they can change it on first login)
- Role: User (not Admin)

Family members log in at `https://mealie.eirdom.homes`.

---

## Importing Recipes

### From a URL (fastest)

Recipes → Create Recipe → Import from URL → paste any recipe URL.

Mealie's scraper works with most major recipe sites — AllRecipes,
NYT Cooking, Serious Eats, Food Network, and thousands more. It
extracts ingredients, steps, cook time, and nutritional info
automatically.

### Manual entry

Recipes → Create Recipe → Create Recipe (manual). Type or paste
the recipe directly.

### From Tandoor / Nextcloud Cookbook / Paprika

Mealie supports importing from other recipe managers via JSON/ZIP
export. Use Recipes → Import/Export.

---

## Meal Planning

### Create a meal plan

Meal Plan → Week view → click any day → Add Recipe.

Assign recipes to breakfast, lunch, dinner, and side slots for each
day. The week view gives a clear overview of what's planned.

### Generate a shopping list

From a meal plan → Shopping Lists → Generate Shopping List.

Mealie combines all ingredients from the week's recipes into a
single de-duplicated list, accounting for ingredient quantities
across multiple recipes.

### Push to Grocy

Configure the Grocy integration to push shopping list items
directly to Grocy:

Settings → Integrations → Grocy:
- Grocy Base URL: `https://grocy.eirdom.homes`
- API Key: from Grocy → Manage API Keys

Once configured, shopping lists can be sent to Grocy with one click.

---

## Recipe Organisation

**Categories** — broad groupings (Breakfast, Dinner, Dessert, Snacks)

**Tags** — more specific labels (Quick, Family Favourite, Make Ahead,
Vegetarian, Gluten-Free)

**Cookbooks** — curated collections (Holiday Recipes, Tyler's Grilling,
Weekly Rotation)

Set these up early and apply them consistently as you import recipes
— search becomes much more useful once recipes are well-tagged.

---

## Storage

```
${DOCKER_DATA_PATH}/mealie/
├── db/     PostgreSQL database files (mealie-db container)
└── data/   Recipe images, exports, other application data
```

Backed up daily by `scripts/backup.sh` — both the PostgreSQL dump
(`mealie-db.sql.gz`) and the data directory tar.

---

## Troubleshooting

### Recipe import fails or imports with missing data

Not all websites use standard recipe markup. For sites that don't
work with the URL importer, use the **Debug Scraper** tool in
Mealie admin to see what data is being extracted. Often you can
fix a partial import by editing the recipe manually.

### Images not showing after import

Check the `mealie/data` directory has correct ownership:

```bash
ls -la /media/arr/config/mealie/data/
# Should be owned by PUID:PGID (1000:1000)
```

Fix with:
```bash
chown -R 1000:1000 /media/arr/config/mealie/
docker compose restart mealie
```

### Family member can't log in

`ALLOW_SIGNUP` is disabled — they need to be invited by the admin.
Check Admin → Manage Users to confirm their account exists and is
active.

---

## Related Documentation

- [`docs/services.md`](../../docs/services.md) — Mealie service entry
- [`docs/decisions.md`](../../docs/decisions.md) — ADR-039
- [`docker/grocy/README.md`](../grocy/README.md) — Grocy integration for shopping lists