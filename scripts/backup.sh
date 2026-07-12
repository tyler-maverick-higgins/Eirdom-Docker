#!/bin/bash
# =============================================================
# backup.sh — Eirdom Backup Script
# Backs up Docker volumes and config data to a NAS or local path
# Usage: sudo bash scripts/backup.sh
# =============================================================

set -euo pipefail

# ============================================================
# COLORS & FORMATTING
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# LOGGING
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$REPO_ROOT/logs"
LOG_FILE="$LOG_DIR/backup_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

log_info()    { echo -e "${BLUE}[INFO]${NC}  $(date '+%H:%M:%S') $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $(date '+%H:%M:%S') $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1"; }
log_section() { echo -e "\n${BOLD}${CYAN}==> $1${NC}"; }

# ============================================================
# LOAD ENVIRONMENT
# ============================================================
ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
    log_error ".env file not found at $ENV_FILE — aborting"
    exit 1
fi

DOCKER_DATA_PATH=$(grep -E '^DOCKER_DATA_PATH=' "$ENV_FILE" | cut -d= -f2 || true)
BACKUP_PATH=$(grep -E '^BACKUP_PATH=' "$ENV_FILE" | cut -d= -f2 || true)
BACKUP_RETENTION_DAYS=$(grep -E '^BACKUP_RETENTION_DAYS=' "$ENV_FILE" | cut -d= -f2 || true)
NAS_HOST=$(grep -E '^NAS_HOST=' "$ENV_FILE" | cut -d= -f2 || true)
NAS_MOUNT=$(grep -E '^NAS_MOUNT=' "$ENV_FILE" | cut -d= -f2 || true)

DOCKER_DATA_PATH=${DOCKER_DATA_PATH:-/media/arr/config}
BACKUP_PATH=${BACKUP_PATH:-/mnt/backup/eirdom}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}

# Load database credentials from service .env files
WP_DB_NAME=$(grep -E '^WP_DB_NAME=' "$REPO_ROOT/docker/webserver/.env" 2>/dev/null | cut -d= -f2 || echo "wordpress")
WP_DB_USER=$(grep -E '^WP_DB_USER=' "$REPO_ROOT/docker/webserver/.env" 2>/dev/null | cut -d= -f2 || echo "wordpress")
WP_DB_PASSWORD=$(grep -E '^WP_DB_PASSWORD=' "$REPO_ROOT/docker/webserver/.env" 2>/dev/null | cut -d= -f2 || true)

AUTHENTIK_DB_NAME=$(grep -E '^AUTHENTIK_DB_NAME=' "$REPO_ROOT/docker/authentik/.env" 2>/dev/null | cut -d= -f2 || echo "authentik")
AUTHENTIK_DB_USER=$(grep -E '^AUTHENTIK_DB_USER=' "$REPO_ROOT/docker/authentik/.env" 2>/dev/null | cut -d= -f2 || echo "authentik")

NETBOX_DB_NAME=$(grep -E '^NETBOX_DB_NAME=' "$REPO_ROOT/docker/netbox/.env" 2>/dev/null | cut -d= -f2 || echo "netbox")
NETBOX_DB_USER=$(grep -E '^NETBOX_DB_USER=' "$REPO_ROOT/docker/netbox/.env" 2>/dev/null | cut -d= -f2 || echo "netbox")

JELLYSTAT_DB_NAME=$(grep -E '^JELLYSTAT_DB_NAME=' "$REPO_ROOT/docker/jellyfin/.env" 2>/dev/null | cut -d= -f2 || echo "jellystat")
JELLYSTAT_DB_USER=$(grep -E '^JELLYSTAT_DB_USER=' "$REPO_ROOT/docker/jellyfin/.env" 2>/dev/null | cut -d= -f2 || echo "jellystat")

PAPERLESS_DB_NAME=$(grep -E '^PAPERLESS_DB_NAME=' "$REPO_ROOT/docker/paperless/.env" 2>/dev/null | cut -d= -f2 || echo "paperless")
PAPERLESS_DB_USER=$(grep -E '^PAPERLESS_DB_USER=' "$REPO_ROOT/docker/paperless/.env" 2>/dev/null | cut -d= -f2 || echo "paperless")

IMMICH_DB_NAME=$(grep -E '^IMMICH_DB_NAME=' "$REPO_ROOT/docker/immich/.env" 2>/dev/null | cut -d= -f2 || echo "immich")
IMMICH_DB_USER=$(grep -E '^IMMICH_DB_USER=' "$REPO_ROOT/docker/immich/.env" 2>/dev/null | cut -d= -f2 || echo "immich")

MEALIE_DB_NAME=$(grep -E '^MEALIE_DB_NAME=' "$REPO_ROOT/docker/mealie/.env" 2>/dev/null | cut -d= -f2 || echo "mealie")
MEALIE_DB_USER=$(grep -E '^MEALIE_DB_USER=' "$REPO_ROOT/docker/mealie/.env" 2>/dev/null | cut -d= -f2 || echo "mealie")

# ============================================================
# CONFIGURATION
# ============================================================
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_PATH/$TIMESTAMP"

# -----------------------------------------------------------
# File-based service backups
# Key: service name  Value: path to back up
# -----------------------------------------------------------
declare -A SERVICES=(
    # Reverse proxy — certs and dynamic config
    ["traefik"]="$DOCKER_DATA_PATH/traefik"

    # Cloudflared — no credentials stored (token in .env)
    # Backing up for any local config overrides
    ["cloudflared"]="$DOCKER_DATA_PATH/cloudflared"

    # WordPress files — DB backed up separately below
    ["wordpress"]="$DOCKER_DATA_PATH/wordpress/html"

    # Authentik — media, templates, custom branding
    # DB backed up separately below
    ["authentik-media"]="$DOCKER_DATA_PATH/authentik/media"
    ["authentik-templates"]="$DOCKER_DATA_PATH/authentik/templates"

    # NetBox — media, reports, scripts
    # DB backed up separately below
    ["netbox-media"]="$DOCKER_DATA_PATH/netbox/media"
    ["netbox-reports"]="$DOCKER_DATA_PATH/netbox/reports"
    ["netbox-scripts"]="$DOCKER_DATA_PATH/netbox/scripts"

    # ARR stack configs
    ["sonarr"]="$DOCKER_DATA_PATH/sonarr"
    ["radarr"]="$DOCKER_DATA_PATH/radarr"
    ["radarr-4k"]="$DOCKER_DATA_PATH/radarr-4k"
    ["sonarr-4k"]="$DOCKER_DATA_PATH/sonarr-4k"
    ["prowlarr"]="$DOCKER_DATA_PATH/prowlarr"
    ["lidarr"]="$DOCKER_DATA_PATH/lidarr"
    ["bazarr"]="$DOCKER_DATA_PATH/bazarr"
    ["qbittorrent"]="$DOCKER_DATA_PATH/qbittorrent"
    ["recyclarr"]="$DOCKER_DATA_PATH/recyclarr"

    # Media server configs
    # Jellystat DB is backed up separately via pg_dump below
    ["jellyfin"]="$DOCKER_DATA_PATH/jellyfin"
    ["jellyseerr"]="$DOCKER_DATA_PATH/jellyseerr"
    ["jellystat-backup-data"]="$DOCKER_DATA_PATH/jellystat/backup-data"

    # Uptime Kuma — SQLite DB inside the data dir
    ["uptime-kuma"]="$DOCKER_DATA_PATH/uptime-kuma"

    # Stirling PDF — config only (stateless, no user data)
    ["stirling-pdf"]="$DOCKER_DATA_PATH/stirling-pdf/configs"

    # Paperless — application data and media
    # DB backed up separately via pg_dump below
    ["paperless-data"]="$DOCKER_DATA_PATH/paperless/data"
    ["paperless-media"]="$DOCKER_DATA_PATH/paperless/media"

    # Immich — DB backed up separately via pg_dump below
    # Media library is NOT backed up — photos are on family
    # devices and the library can be re-imported if needed
    # Profile photos and thumbnails are regenerated automatically

    # Ntfy — SQLite cache and auth DB
    ["ntfy"]="$DOCKER_DATA_PATH/ntfy"

    # Homebox — SQLite database included in data dir
    ["homebox"]="$DOCKER_DATA_PATH/homebox"

    # Grocy — SQLite database included in config dir
    ["grocy"]="$DOCKER_DATA_PATH/grocy"

    # Mealie — DB backed up separately via pg_dump below
    ["mealie-data"]="$DOCKER_DATA_PATH/mealie/data"

    # Actual Budget — SQLite database included in data dir
    ["actual"]="$DOCKER_DATA_PATH/actual"
)

# -----------------------------------------------------------
# Services to stop before backing up
# Ensures SQLite databases are not mid-write during backup
# -----------------------------------------------------------
STOP_FOR_BACKUP=(
    "sonarr"
    "sonarr-4k"
    "radarr"
    "radarr-4k"
    "prowlarr"
    "lidarr"
    "bazarr"
    "jellyfin"
    "jellyseerr"
)

# ============================================================
# TRACKING
# ============================================================
BACKUP_SUCCESS=()
BACKUP_FAILED=()

# ============================================================
# BANNER
# ============================================================
echo -e "${BOLD}${CYAN}"
echo "  ███████╗██╗██████╗ ██████╗  ██████╗ ███╗   ███╗"
echo "  ██╔════╝██║██╔══██╗██╔══██╗██╔═══██╗████╗ ████║"
echo "  █████╗  ██║██████╔╝██║  ██║██║   ██║██╔████╔██║"
echo "  ██╔══╝  ██║██╔══██╗██║  ██║██║   ██║██║╚██╔╝██║"
echo "  ███████╗██║██║  ██║██████╔╝╚██████╔╝██║ ╚═╝ ██║"
echo "  ╚══════╝╚═╝╚═╝  ╚═╝╚═════╝  ╚═════╝ ╚═╝     ╚═╝"
echo -e "${NC}"
echo -e "${BOLD}  Eirdom — Backup Script${NC}"
echo    "  ----------------------------------------"
echo    "  Started:    $(date '+%Y-%m-%d %H:%M:%S')"
echo    "  Backup dir: $BACKUP_DIR"
echo    "  Retention:  $BACKUP_RETENTION_DAYS days"
echo    "  Log:        $LOG_FILE"
echo

# ============================================================
# PREFLIGHT CHECKS
# ============================================================
log_section "Preflight Checks"

if ! docker info &>/dev/null; then
    log_error "Docker is not running — aborting"
    exit 1
fi
log_success "Docker is running"

if [ ! -d "$DOCKER_DATA_PATH" ]; then
    log_error "Docker data path not found: $DOCKER_DATA_PATH"
    exit 1
fi
log_success "Docker data path found: $DOCKER_DATA_PATH"

# ============================================================
# NAS MOUNT CHECK (optional)
# ============================================================
log_section "Storage Check"

if [ -n "${NAS_HOST:-}" ] && [ -n "${NAS_MOUNT:-}" ]; then
    log_info "NAS configured: $NAS_HOST → $NAS_MOUNT"

    if mountpoint -q "$NAS_MOUNT"; then
        log_success "NAS already mounted at $NAS_MOUNT"
    else
        log_info "Mounting NAS..."
        if mount "$NAS_MOUNT" 2>/dev/null; then
            log_success "NAS mounted at $NAS_MOUNT"
        else
            log_error "Failed to mount NAS at $NAS_MOUNT — aborting"
            log_error "Check /etc/fstab entry for $NAS_MOUNT"
            exit 1
        fi
    fi

    AVAILABLE_KB=$(df -k "$NAS_MOUNT" | awk 'NR==2 {print $4}')
    AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))
    if [ "$AVAILABLE_GB" -lt 10 ]; then
        log_warn "Low disk space on NAS: ${AVAILABLE_GB}GB available"
    else
        log_success "NAS disk space: ${AVAILABLE_GB}GB available"
    fi
else
    log_info "No NAS configured — backing up to local path: $BACKUP_PATH"
    if [ -d "$BACKUP_PATH" ]; then
        AVAILABLE_KB=$(df -k "$BACKUP_PATH" | awk 'NR==2 {print $4}')
        AVAILABLE_GB=$((AVAILABLE_KB / 1024 / 1024))
        if [ "$AVAILABLE_GB" -lt 10 ]; then
            log_warn "Low disk space: ${AVAILABLE_GB}GB available at $BACKUP_PATH"
        else
            log_success "Disk space: ${AVAILABLE_GB}GB available"
        fi
    fi
fi

mkdir -p "$BACKUP_DIR"
log_success "Created backup directory: $BACKUP_DIR"

# ============================================================
# DATABASE DUMPS
# Hot backups — no container stop required for PostgreSQL/MySQL
# pg_dump and mysqldump are transactionally consistent
# ============================================================
log_section "Database Dumps"

# -----------------------------------------------------------
# WordPress — MariaDB dump
# -----------------------------------------------------------
if docker ps --format "{{.Names}}" | grep -q "^mariadb$"; then
    log_info "Dumping WordPress MariaDB database..."
    WP_DUMP="$BACKUP_DIR/wordpress-db.sql.gz"
    if docker exec mariadb sh -c \
        "mysqldump -u${WP_DB_USER} -p${WP_DB_PASSWORD} ${WP_DB_NAME}" \
        2>/dev/null | gzip > "$WP_DUMP"; then
        SIZE=$(du -sh "$WP_DUMP" | cut -f1)
        log_success "WordPress DB → wordpress-db.sql.gz ($SIZE)"
        BACKUP_SUCCESS+=("wordpress-db ($SIZE)")
    else
        log_error "WordPress DB dump failed"
        BACKUP_FAILED+=("wordpress-db (dump error)")
        rm -f "$WP_DUMP"
    fi
else
    log_warn "mariadb container not running — skipping WordPress DB dump"
    BACKUP_FAILED+=("wordpress-db (container not running)")
fi

# -----------------------------------------------------------
# Authentik — PostgreSQL dump
# -----------------------------------------------------------
if docker ps --format "{{.Names}}" | grep -q "^authentik-postgres$"; then
    log_info "Dumping Authentik PostgreSQL database..."
    AUTH_DUMP="$BACKUP_DIR/authentik-db.sql.gz"
    if docker exec authentik-postgres \
        pg_dump -U "$AUTHENTIK_DB_USER" "$AUTHENTIK_DB_NAME" \
        2>/dev/null | gzip > "$AUTH_DUMP"; then
        SIZE=$(du -sh "$AUTH_DUMP" | cut -f1)
        log_success "Authentik DB → authentik-db.sql.gz ($SIZE)"
        BACKUP_SUCCESS+=("authentik-db ($SIZE)")
    else
        log_error "Authentik DB dump failed"
        BACKUP_FAILED+=("authentik-db (dump error)")
        rm -f "$AUTH_DUMP"
    fi
else
    log_warn "authentik-postgres container not running — skipping Authentik DB dump"
    BACKUP_FAILED+=("authentik-db (container not running)")
fi

# -----------------------------------------------------------
# NetBox — PostgreSQL dump
# -----------------------------------------------------------
if docker ps --format "{{.Names}}" | grep -q "^netbox-postgres$"; then
    log_info "Dumping NetBox PostgreSQL database..."
    NB_DUMP="$BACKUP_DIR/netbox-db.sql.gz"
    if docker exec netbox-postgres \
        pg_dump -U "$NETBOX_DB_USER" "$NETBOX_DB_NAME" \
        2>/dev/null | gzip > "$NB_DUMP"; then
        SIZE=$(du -sh "$NB_DUMP" | cut -f1)
        log_success "NetBox DB → netbox-db.sql.gz ($SIZE)"
        BACKUP_SUCCESS+=("netbox-db ($SIZE)")
    else
        log_error "NetBox DB dump failed"
        BACKUP_FAILED+=("netbox-db (dump error)")
        rm -f "$NB_DUMP"
    fi
else
    log_warn "netbox-postgres container not running — skipping NetBox DB dump"
    BACKUP_FAILED+=("netbox-db (container not running)")
fi

# -----------------------------------------------------------
# Jellystat — PostgreSQL dump
# -----------------------------------------------------------
if docker ps --format "{{.Names}}" | grep -q "^jellystat-db$"; then
    log_info "Dumping Jellystat PostgreSQL database..."
    JS_DUMP="$BACKUP_DIR/jellystat-db.sql.gz"
    if docker exec jellystat-db \
        pg_dump -U "$JELLYSTAT_DB_USER" "$JELLYSTAT_DB_NAME" \
        2>/dev/null | gzip > "$JS_DUMP"; then
        SIZE=$(du -sh "$JS_DUMP" | cut -f1)
        log_success "Jellystat DB → jellystat-db.sql.gz ($SIZE)"
        BACKUP_SUCCESS+=("jellystat-db ($SIZE)")
    else
        log_error "Jellystat DB dump failed"
        BACKUP_FAILED+=("jellystat-db (dump error)")
        rm -f "$JS_DUMP"
    fi
else
    log_warn "jellystat-db container not running — skipping Jellystat DB dump"
    BACKUP_FAILED+=("jellystat-db (container not running)")
fi

# -----------------------------------------------------------
# Paperless — PostgreSQL dump
# -----------------------------------------------------------
if docker ps --format "{{.Names}}" | grep -q "^paperless-db$"; then
    log_info "Dumping Paperless PostgreSQL database..."
    PL_DUMP="$BACKUP_DIR/paperless-db.sql.gz"
    if docker exec paperless-db \
        pg_dump -U "$PAPERLESS_DB_USER" "$PAPERLESS_DB_NAME" \
        2>/dev/null | gzip > "$PL_DUMP"; then
        SIZE=$(du -sh "$PL_DUMP" | cut -f1)
        log_success "Paperless DB → paperless-db.sql.gz ($SIZE)"
        BACKUP_SUCCESS+=("paperless-db ($SIZE)")
    else
        log_error "Paperless DB dump failed"
        BACKUP_FAILED+=("paperless-db (dump error)")
        rm -f "$PL_DUMP"
    fi
else
    log_warn "paperless-db container not running — skipping Paperless DB dump"
    BACKUP_FAILED+=("paperless-db (container not running)")
fi

# -----------------------------------------------------------
# Immich — PostgreSQL dump
# Media library is intentionally NOT backed up here —
# source photos live on family devices and the library can
# be re-imported. The DB backup preserves albums, faces,
# tags, shares, and all metadata.
# -----------------------------------------------------------
if docker ps --format "{{.Names}}" | grep -q "^immich-db$"; then
    log_info "Dumping Immich PostgreSQL database..."
    IM_DUMP="$BACKUP_DIR/immich-db.sql.gz"
    if docker exec immich-db \
        pg_dump -U "$IMMICH_DB_USER" "$IMMICH_DB_NAME" \
        2>/dev/null | gzip > "$IM_DUMP"; then
        SIZE=$(du -sh "$IM_DUMP" | cut -f1)
        log_success "Immich DB → immich-db.sql.gz ($SIZE)"
        BACKUP_SUCCESS+=("immich-db ($SIZE)")
    else
        log_error "Immich DB dump failed"
        BACKUP_FAILED+=("immich-db (dump error)")
        rm -f "$IM_DUMP"
    fi
else
    log_warn "immich-db container not running — skipping Immich DB dump"
    BACKUP_FAILED+=("immich-db (container not running)")
fi

# -----------------------------------------------------------
# Mealie — PostgreSQL dump
# -----------------------------------------------------------
if docker ps --format "{{.Names}}" | grep -q "^mealie-db$"; then
    log_info "Dumping Mealie PostgreSQL database..."
    ML_DUMP="$BACKUP_DIR/mealie-db.sql.gz"
    if docker exec mealie-db \
        pg_dump -U "$MEALIE_DB_USER" "$MEALIE_DB_NAME" \
        2>/dev/null | gzip > "$ML_DUMP"; then
        SIZE=$(du -sh "$ML_DUMP" | cut -f1)
        log_success "Mealie DB → mealie-db.sql.gz ($SIZE)"
        BACKUP_SUCCESS+=("mealie-db ($SIZE)")
    else
        log_error "Mealie DB dump failed"
        BACKUP_FAILED+=("mealie-db (dump error)")
        rm -f "$ML_DUMP"
    fi
else
    log_warn "mealie-db container not running — skipping Mealie DB dump"
    BACKUP_FAILED+=("mealie-db (container not running)")
fi

# ============================================================
# STOP SERVICES FOR CONSISTENT FILE BACKUP
# ARR apps and Jellyfin use SQLite — stop before tar to prevent
# backing up a mid-write database file
# PostgreSQL/MariaDB use pg_dump/mysqldump above — no stop needed
# ============================================================
log_section "Stopping Services for Consistent Backup"

STOPPED_SERVICES=()

for service in "${STOP_FOR_BACKUP[@]}"; do
    # Determine which compose file owns this service
    if [[ "$service" =~ ^(sonarr|sonarr-4k|radarr|radarr-4k|prowlarr|lidarr|bazarr)$ ]]; then
        COMPOSE_FILE="$REPO_ROOT/docker/arr-stack/docker-compose.yml"
    elif [[ "$service" =~ ^(jellyfin|jellyseerr)$ ]]; then
        COMPOSE_FILE="$REPO_ROOT/docker/jellyfin/docker-compose.yml"
    else
        COMPOSE_FILE=""
    fi

    if [ -n "$COMPOSE_FILE" ] && [ -f "$COMPOSE_FILE" ]; then
        if docker compose -f "$COMPOSE_FILE" ps --services \
            --filter "status=running" 2>/dev/null | grep -q "^${service}$"; then
            log_info "Stopping $service..."
            docker compose -f "$COMPOSE_FILE" stop "$service" 2>/dev/null
            STOPPED_SERVICES+=("$service:$COMPOSE_FILE")
            log_success "$service stopped"
        else
            log_info "$service is not running — skipping stop"
        fi
    fi
done

# ============================================================
# FILE-BASED SERVICE BACKUPS
# ============================================================
log_section "Backing Up Service Files"

for service in "${!SERVICES[@]}"; do
    SOURCE="${SERVICES[$service]}"
    DEST="$BACKUP_DIR/${service}.tar.gz"

    if [ ! -d "$SOURCE" ]; then
        log_warn "$service — source path not found: $SOURCE — skipping"
        BACKUP_FAILED+=("$service (source not found)")
        continue
    fi

    log_info "Backing up $service..."

    if tar -czf "$DEST" -C "$(dirname "$SOURCE")" "$(basename "$SOURCE")" 2>/dev/null; then
        SIZE=$(du -sh "$DEST" | cut -f1)
        log_success "$service → ${service}.tar.gz ($SIZE)"
        BACKUP_SUCCESS+=("$service ($SIZE)")
    else
        log_error "$service — backup failed"
        BACKUP_FAILED+=("$service (tar error)")
        rm -f "$DEST"
    fi
done

# ============================================================
# RESTART STOPPED SERVICES
# ============================================================
log_section "Restarting Services"

if [ ${#STOPPED_SERVICES[@]} -eq 0 ]; then
    log_info "No services were stopped — nothing to restart"
else
    for entry in "${STOPPED_SERVICES[@]}"; do
        service="${entry%%:*}"
        compose_file="${entry##*:}"
        log_info "Restarting $service..."
        docker compose -f "$compose_file" start "$service" 2>/dev/null
        log_success "$service restarted"
    done
fi

# ============================================================
# BACKUP REPO CONFIG FILES
# ============================================================
log_section "Backing Up Repo Config"

REPO_DEST="$BACKUP_DIR/eirdom-repo.tar.gz"

tar -czf "$REPO_DEST" \
    -C "$(dirname "$REPO_ROOT")" \
    --exclude="*.env" \
    --exclude="*/logs/*" \
    --exclude="*/.git/*" \
    --exclude="*/node_modules/*" \
    "$(basename "$REPO_ROOT")" 2>/dev/null

SIZE=$(du -sh "$REPO_DEST" | cut -f1)
log_success "Repo config → eirdom-repo.tar.gz ($SIZE)"
BACKUP_SUCCESS+=("eirdom-repo ($SIZE)")

# ============================================================
# WRITE BACKUP MANIFEST
# ============================================================
log_section "Writing Manifest"

MANIFEST="$BACKUP_DIR/manifest.txt"

{
    echo "========================================"
    echo "  Eirdom Backup Manifest"
    echo "========================================"
    echo "  Date:       $(date '+%Y-%m-%d %H:%M:%S')"
    echo "  Hostname:   $(hostname)"
    echo "  Backup dir: $BACKUP_DIR"
    echo ""
    echo "  Successful Backups:"
    for s in "${BACKUP_SUCCESS[@]}"; do
        echo "    ✓ $s"
    done
    if [ ${#BACKUP_FAILED[@]} -gt 0 ]; then
        echo ""
        echo "  Failed Backups:"
        for f in "${BACKUP_FAILED[@]}"; do
            echo "    ✗ $f"
        done
    fi
    echo ""
    echo "  Files:"
    ls -lh "$BACKUP_DIR"
    echo ""
    echo "  Total size:"
    du -sh "$BACKUP_DIR"
    echo "========================================"
} > "$MANIFEST"

log_success "Manifest written to $MANIFEST"

# ============================================================
# PRUNE OLD BACKUPS
# ============================================================
log_section "Pruning Old Backups"

if [ -d "$BACKUP_PATH" ]; then
    PRUNED=0
    while IFS= read -r old_backup; do
        log_info "Removing old backup: $(basename "$old_backup")"
        rm -rf "$old_backup"
        ((PRUNED++))
    done < <(find "$BACKUP_PATH" -maxdepth 1 -mindepth 1 -type d \
        -mtime +"$BACKUP_RETENTION_DAYS" 2>/dev/null)

    if [ "$PRUNED" -eq 0 ]; then
        log_info "No backups older than $BACKUP_RETENTION_DAYS days found"
    else
        log_success "Pruned $PRUNED old backup(s)"
    fi
fi

# ============================================================
# SUMMARY
# ============================================================
log_section "Backup Complete"

TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

echo
echo -e "${BOLD}  Results:${NC}"
echo    "  ----------------------------------------"
echo -e "  ${GREEN}Successful:${NC} ${#BACKUP_SUCCESS[@]}"
for s in "${BACKUP_SUCCESS[@]}"; do
    echo    "    ✓ $s"
done

if [ ${#BACKUP_FAILED[@]} -gt 0 ]; then
    echo -e "  ${RED}Failed:${NC} ${#BACKUP_FAILED[@]}"
    for f in "${BACKUP_FAILED[@]}"; do
        echo "    ✗ $f"
    done
fi

echo
echo    "  Total backup size: $TOTAL_SIZE"
echo    "  Location:          $BACKUP_DIR"
echo    "  Log:               $LOG_FILE"
echo    "  Finished:          $(date '+%Y-%m-%d %H:%M:%S')"
echo

if [ ${#BACKUP_FAILED[@]} -gt 0 ]; then
    log_warn "Backup completed with errors — review log: $LOG_FILE"

    # Notify via ntfy — backup failed
    if [ -n "${NTFY_TOKEN:-}" ]; then
        curl -s \
            -H "Authorization: Bearer $NTFY_TOKEN" \
            -H "Title: Eirdom Backup Failed" \
            -H "Priority: high" \
            -H "Tags: warning" \
            -d "Backup completed with ${#BACKUP_FAILED[@]} failure(s). Review: $LOG_FILE" \
            "https://ntfy.${ROOT_DOMAIN:-eirdom.homes}/eirdom-backup" > /dev/null 2>&1 || true
    fi

    exit 1
else
    log_success "All backups completed successfully"

    # Notify via ntfy — backup succeeded
    if [ -n "${NTFY_TOKEN:-}" ]; then
        curl -s \
            -H "Authorization: Bearer $NTFY_TOKEN" \
            -H "Title: Eirdom Backup Complete" \
            -H "Tags: white_check_mark" \
            -d "All ${#BACKUP_SUCCESS[@]} backup(s) completed. Size: $TOTAL_SIZE" \
            "https://ntfy.${ROOT_DOMAIN:-eirdom.homes}/eirdom-backup" > /dev/null 2>&1 || true
    fi

    exit 0
fi