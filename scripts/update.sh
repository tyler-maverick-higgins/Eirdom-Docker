#!/bin/bash
# =============================================================
# update.sh — Eirdom Update Script
# Pulls latest Docker images and recreates changed containers
# Usage: sudo bash scripts/update.sh [service]
#        sudo bash scripts/update.sh          # updates everything
#        sudo bash scripts/update.sh traefik  # updates one service
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
LOG_FILE="$LOG_DIR/update_$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log_info()    { echo -e "${BLUE}[INFO]${NC}  $(date '+%H:%M:%S') $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $(date '+%H:%M:%S') $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $(date '+%H:%M:%S') $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1"; }
log_section() { echo -e "\n${BOLD}${CYAN}==> $1${NC}"; }

# ============================================================
# ROOT CHECK
# ============================================================
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    exit 1
fi

# ============================================================
# SERVICE REGISTRY
# Order matters — determines startup and update sequence.
# Traefik must always be first. Authentik before everything
# that depends on ForwardAuth. NetBox last (custom image build).
# ============================================================
declare -A SERVICE_COMPOSE=(
    ["traefik"]="docker/traefik/docker-compose.yml"
    ["authentik"]="docker/authentik/docker-compose.yml"
    ["cloudflared"]="docker/cloudflared/docker-compose.yml"
    ["webserver"]="docker/webserver/docker-compose.yml"
    ["arr-stack"]="docker/arr-stack/docker-compose.yml"
    ["jellyfin"]="docker/jellyfin/docker-compose.yml"
    ["netbox"]="docker/netbox/docker-compose.yml"
    ["uptime-kuma"]="docker/uptime-kuma/docker-compose.yml"
    ["stirling-pdf"]="docker/stirling-pdf/docker-compose.yml"
    ["paperless"]="docker/paperless/docker-compose.yml"
    ["immich"]="docker/immich/docker-compose.yml"
    ["ntfy"]="docker/ntfy/docker-compose.yml"
    ["homebox"]="docker/homebox/docker-compose.yml"
    ["grocy"]="docker/grocy/docker-compose.yml"
    ["mealie"]="docker/mealie/docker-compose.yml"
    ["actual"]="docker/actual/docker-compose.yml"
)

# Startup order — strictly enforced
SERVICE_ORDER=(
    "traefik"
    "authentik"
    "cloudflared"
    "webserver"
    "arr-stack"
    "jellyfin"
    "netbox"
    "uptime-kuma"
    "stirling-pdf"
    "paperless"
    "immich"
    "ntfy"
    "homebox"
    "grocy"
    "mealie"
    "actual"
)

# Services that use a custom locally-built image
# These must be rebuilt (docker compose build) rather than
# just pulled — they extend the base image with plugins
CUSTOM_BUILD_SERVICES=(
    "netbox"
)

# ============================================================
# PARSE ARGUMENTS
# ============================================================
TARGET_SERVICE="${1:-all}"

if [ "$TARGET_SERVICE" != "all" ]; then
    if [[ ! -v SERVICE_COMPOSE["$TARGET_SERVICE"] ]]; then
        log_error "Unknown service: $TARGET_SERVICE"
        echo
        echo "  Available services:"
        for svc in "${SERVICE_ORDER[@]}"; do
            echo "    - $svc"
        done
        echo
        exit 1
    fi
fi

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
echo -e "${BOLD}  Eirdom — Update Script${NC}"
echo    "  ----------------------------------------"
echo    "  Started: $(date '+%Y-%m-%d %H:%M:%S')"
echo    "  Target:  $TARGET_SERVICE"
echo    "  Log:     $LOG_FILE"
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

if ! ping -c 1 8.8.8.8 &>/dev/null; then
    log_error "No internet connectivity — aborting"
    exit 1
fi
log_success "Internet connectivity confirmed"

# ============================================================
# PRE-UPDATE BACKUP
# ============================================================
log_section "Pre-Update Backup"

BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"

if [ -f "$BACKUP_SCRIPT" ]; then
    log_info "Running backup before update..."
    if bash "$BACKUP_SCRIPT"; then
        log_success "Pre-update backup completed"
    else
        log_warn "Backup reported errors — review backup log before continuing"
        echo
        read -r -p "  Continue with update anyway? [y/N] " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_info "Update cancelled by user"
            exit 0
        fi
    fi
else
    log_warn "backup.sh not found — skipping pre-update backup"
    log_warn "It is strongly recommended to back up before updating"
    echo
    read -r -p "  Continue without backup? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Update cancelled by user"
        exit 0
    fi
fi

# ============================================================
# BUILD SERVICE LIST TO UPDATE
# ============================================================
if [ "$TARGET_SERVICE" = "all" ]; then
    SERVICES_TO_UPDATE=("${SERVICE_ORDER[@]}")
else
    SERVICES_TO_UPDATE=("$TARGET_SERVICE")
fi

# ============================================================
# TRACKING
# ============================================================
UPDATE_SUCCESS=()
UPDATE_FAILED=()
UPDATE_SKIPPED=()
REBUILT_IMAGES=()

declare -A IMAGE_BEFORE
declare -A IMAGE_AFTER

# ============================================================
# SPECIAL HANDLING: AUTHENTIK UPGRADE WARNING
# Authentik does not support downgrading and upgrades must
# follow sequential major versions. Warn before updating.
# ============================================================
for service in "${SERVICES_TO_UPDATE[@]}"; do
    if [ "$service" = "authentik" ]; then
        COMPOSE_FILE="$REPO_ROOT/${SERVICE_COMPOSE[$service]}"
        if [ -f "$COMPOSE_FILE" ]; then
            CURRENT_TAG=$(grep -E 'image:.*goauthentik' "$COMPOSE_FILE" | head -1 | grep -oE '[0-9]{4}\.[0-9]+' || echo "unknown")
            echo
            log_warn "=========================================="
            log_warn "AUTHENTIK UPGRADE WARNING"
            log_warn "=========================================="
            log_warn "Current version tag in compose: $CURRENT_TAG"
            log_warn "Authentik does NOT support downgrading."
            log_warn "Always back up the Authentik PostgreSQL"
            log_warn "database before upgrading."
            log_warn "Review release notes at:"
            log_warn "  docs.goauthentik.io/releases/"
            log_warn "=========================================="
            echo
            read -r -p "  Confirmed — proceed with Authentik update? [y/N] " auth_confirm
            if [[ ! "$auth_confirm" =~ ^[Yy]$ ]]; then
                log_info "Removing authentik from update list"
                SERVICES_TO_UPDATE=("${SERVICES_TO_UPDATE[@]/authentik}")
            fi
        fi
        break
    fi
done

# ============================================================
# SPECIAL HANDLING: NETBOX UPGRADE WARNING
# NetBox upgrades must follow sequential major versions.
# Custom image must be rebuilt after version bump.
# ============================================================
for service in "${SERVICES_TO_UPDATE[@]}"; do
    if [ "$service" = "netbox" ]; then
        COMPOSE_FILE="$REPO_ROOT/${SERVICE_COMPOSE[$service]}"
        if [ -f "$COMPOSE_FILE" ]; then
            CURRENT_TAG=$(grep -E 'NETBOX_VERSION' "$COMPOSE_FILE" | head -1 | grep -oE 'v[0-9]+\.[0-9]+' || echo "unknown")
            echo
            log_warn "=========================================="
            log_warn "NETBOX UPGRADE NOTE"
            log_warn "=========================================="
            log_warn "Current version in compose: $CURRENT_TAG"
            log_warn "NetBox uses a custom image (eirdom/netbox)."
            log_warn "Updating NetBox rebuilds the custom image"
            log_warn "with the new base version + plugins."
            log_warn "Back up NetBox PostgreSQL before upgrading."
            log_warn "Review release notes at:"
            log_warn "  netboxlabs.com/docs/netbox/release-notes/"
            log_warn "=========================================="
            echo
            read -r -p "  Confirmed — proceed with NetBox update? [y/N] " nb_confirm
            if [[ ! "$nb_confirm" =~ ^[Yy]$ ]]; then
                log_info "Removing netbox from update list"
                SERVICES_TO_UPDATE=("${SERVICES_TO_UPDATE[@]/netbox}")
            fi
        fi
        break
    fi
done

# ============================================================
# PULL / BUILD UPDATED IMAGES
# ============================================================
log_section "Updating Images"

for service in "${SERVICES_TO_UPDATE[@]}"; do
    # Skip empty entries (services removed from update list above)
    [ -z "$service" ] && continue

    COMPOSE_FILE="$REPO_ROOT/${SERVICE_COMPOSE[$service]}"

    if [ ! -f "$COMPOSE_FILE" ]; then
        log_warn "$service — compose file not found: $COMPOSE_FILE — skipping"
        UPDATE_SKIPPED+=("$service (compose file not found)")
        continue
    fi

    # Check if this service uses a custom build
    IS_CUSTOM_BUILD=false
    for custom_svc in "${CUSTOM_BUILD_SERVICES[@]}"; do
        if [ "$custom_svc" = "$service" ]; then
            IS_CUSTOM_BUILD=true
            break
        fi
    done

    if [ "$IS_CUSTOM_BUILD" = true ]; then
        # Custom build services — rebuild the image
        log_info "$service — rebuilding custom image..."
        IMAGE_BEFORE[$service]=$(docker compose -f "$COMPOSE_FILE" images -q 2>/dev/null | sort | tr '\n' ',' || echo "unknown")

        if docker compose -f "$COMPOSE_FILE" build --pull 2>/dev/null; then
            log_success "$service — custom image rebuilt"
            REBUILT_IMAGES+=("$service")
        else
            log_error "$service — image build failed"
            UPDATE_FAILED+=("$service (build failed)")
            continue
        fi

        IMAGE_AFTER[$service]=$(docker compose -f "$COMPOSE_FILE" images -q 2>/dev/null | sort | tr '\n' ',' || echo "unknown")
    else
        # Standard services — pull latest image
        log_info "$service — pulling latest images..."
        IMAGE_BEFORE[$service]=$(docker compose -f "$COMPOSE_FILE" images -q 2>/dev/null | sort | tr '\n' ',' || echo "unknown")

        if docker compose -f "$COMPOSE_FILE" pull 2>/dev/null; then
            log_success "$service — images pulled"
        else
            log_error "$service — pull failed"
            UPDATE_FAILED+=("$service (pull failed)")
            continue
        fi

        IMAGE_AFTER[$service]=$(docker compose -f "$COMPOSE_FILE" images -q 2>/dev/null | sort | tr '\n' ',' || echo "unknown")

        # Check if anything actually changed
        if [ "${IMAGE_BEFORE[$service]}" = "${IMAGE_AFTER[$service]}" ]; then
            log_info "$service — already up to date"
            UPDATE_SKIPPED+=("$service (already up to date)")
        else
            log_success "$service — new images available"
        fi
    fi
done

# ============================================================
# RECREATE CONTAINERS
# ============================================================
log_section "Recreating Containers"

for service in "${SERVICES_TO_UPDATE[@]}"; do
    [ -z "$service" ] && continue

    COMPOSE_FILE="$REPO_ROOT/${SERVICE_COMPOSE[$service]}"

    # Skip if already marked as failed
    if printf '%s\n' "${UPDATE_FAILED[@]}" | grep -q "^$service"; then
        log_warn "$service — skipping restart due to earlier failure"
        continue
    fi

    # Skip if compose file not found
    if printf '%s\n' "${UPDATE_SKIPPED[@]}" | grep -q "^$service (compose file not found)"; then
        continue
    fi

    if [ ! -f "$COMPOSE_FILE" ]; then
        continue
    fi

    log_info "$service — recreating containers..."

    if docker compose -f "$COMPOSE_FILE" up -d --remove-orphans 2>/dev/null; then
        log_success "$service — containers recreated"

        # Only count as success if images changed or were rebuilt
        if ! printf '%s\n' "${UPDATE_SKIPPED[@]}" | grep -q "^$service (already up to date)"; then
            UPDATE_SUCCESS+=("$service")
        fi
    else
        log_error "$service — failed to recreate containers"
        UPDATE_FAILED+=("$service (recreate failed)")
    fi

    # Brief pause between services to allow dependencies to stabilize
    # Traefik and Authentik in particular need a moment before
    # downstream services start routing through them
    if [ "$service" = "traefik" ] || [ "$service" = "authentik" ]; then
        log_info "Waiting 15 seconds for $service to stabilize..."
        sleep 15
    fi
done

# ============================================================
# HEALTH CHECKS
# ============================================================
log_section "Health Checks"

log_info "Waiting 20 seconds for containers to initialize..."
sleep 20

for service in "${SERVICES_TO_UPDATE[@]}"; do
    [ -z "$service" ] && continue

    COMPOSE_FILE="$REPO_ROOT/${SERVICE_COMPOSE[$service]}"

    if [ ! -f "$COMPOSE_FILE" ]; then
        continue
    fi

    CONTAINERS=$(docker compose -f "$COMPOSE_FILE" ps --format "{{.Name}}" 2>/dev/null || true)

    if [ -z "$CONTAINERS" ]; then
        log_warn "$service — no running containers found after update"
        continue
    fi

    ALL_HEALTHY=true

    while IFS= read -r container; do
        [ -z "$container" ] && continue
        STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "unknown")
        HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null || echo "unknown")

        if [ "$STATUS" = "running" ]; then
            if [ "$HEALTH" = "unhealthy" ]; then
                log_warn "$container — running but unhealthy"
                ALL_HEALTHY=false
            elif [ "$HEALTH" = "none" ] || [ "$HEALTH" = "healthy" ]; then
                log_success "$container — running"
            else
                log_info "$container — running (health: $HEALTH)"
            fi
        else
            log_error "$container — status: $STATUS"
            ALL_HEALTHY=false
        fi
    done <<< "$CONTAINERS"

    if [ "$ALL_HEALTHY" = false ]; then
        log_warn "$service — one or more containers need attention"
        log_warn "Run: docker compose -f $COMPOSE_FILE logs --tail 50"
    fi
done

# ============================================================
# PRUNE OLD IMAGES
# ============================================================
log_section "Pruning Old Images"

log_info "Removing dangling images..."
PRUNED=$(docker image prune -f 2>/dev/null | tail -1 || echo "0B reclaimed")
log_success "Pruned dangling images — $PRUNED"

# ============================================================
# POST-UPDATE REMINDERS
# ============================================================

# Check if Authentik was updated — outpost version must match
AUTHENTIK_UPDATED=false
for s in "${UPDATE_SUCCESS[@]}"; do
    [ "$s" = "authentik" ] && AUTHENTIK_UPDATED=true
done

# Check if NetBox was updated — migrations may need to run
NETBOX_UPDATED=false
for s in "${UPDATE_SUCCESS[@]}"; do
    [ "$s" = "netbox" ] && NETBOX_UPDATED=true
done

# ============================================================
# SUMMARY
# ============================================================
log_section "Update Complete"

echo
echo -e "${BOLD}  Results:${NC}"
echo    "  ----------------------------------------"

if [ ${#UPDATE_SUCCESS[@]} -gt 0 ]; then
    echo -e "  ${GREEN}Updated (${#UPDATE_SUCCESS[@]}):${NC}"
    for s in "${UPDATE_SUCCESS[@]}"; do
        echo    "    ✓ $s"
    done
fi

if [ ${#REBUILT_IMAGES[@]} -gt 0 ]; then
    echo -e "  ${BLUE}Rebuilt (${#REBUILT_IMAGES[@]}):${NC}"
    for s in "${REBUILT_IMAGES[@]}"; do
        echo    "    ↺ $s (custom image)"
    done
fi

if [ ${#UPDATE_SKIPPED[@]} -gt 0 ]; then
    echo -e "  ${BLUE}Skipped (${#UPDATE_SKIPPED[@]}):${NC}"
    for s in "${UPDATE_SKIPPED[@]}"; do
        echo    "    - $s"
    done
fi

if [ ${#UPDATE_FAILED[@]} -gt 0 ]; then
    echo -e "  ${RED}Failed (${#UPDATE_FAILED[@]}):${NC}"
    for f in "${UPDATE_FAILED[@]}"; do
        echo    "    ✗ $f"
    done
fi

echo

# Post-update action reminders
if [ "$AUTHENTIK_UPDATED" = true ]; then
    echo -e "  ${YELLOW}Authentik updated — action required:${NC}"
    echo    "    → Verify embedded outpost version matches server version"
    echo    "    → In Authentik admin: Applications → Outposts → check version"
    echo    "    → Outpost and server versions must match exactly"
    echo
fi

if [ "$NETBOX_UPDATED" = true ]; then
    echo -e "  ${YELLOW}NetBox updated — action required:${NC}"
    echo    "    → Run database migrations:"
    echo    "      docker exec netbox /opt/netbox/venv/bin/python"
    echo    "        /opt/netbox/netbox/manage.py migrate"
    echo    "    → Run UniFi sync plugin migrations:"
    echo    "      docker exec netbox /opt/netbox/venv/bin/python"
    echo    "        /opt/netbox/netbox/manage.py migrate netbox_unifi_sync"
    echo
fi

echo    "  Log: $LOG_FILE"
echo    "  Finished: $(date '+%Y-%m-%d %H:%M:%S')"
echo

if [ ${#UPDATE_FAILED[@]} -gt 0 ]; then
    log_warn "Update completed with errors — review log: $LOG_FILE"
    exit 1
else
    log_success "Update completed successfully"
    exit 0
fi