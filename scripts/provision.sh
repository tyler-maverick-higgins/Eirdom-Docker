#!/bin/bash
# =============================================================
# provision.sh — Eirdom Initial Server Setup
# Run once after cloning on a new server
# Usage: sudo bash scripts/provision.sh
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
log_info()    { echo -e "${BLUE}[INFO]${NC}  $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BOLD}${CYAN}==> $1${NC}"; }

# ============================================================
# ROOT CHECK
# ============================================================
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root or with sudo"
    exit 1
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
echo -e "${BOLD}  Eirdom — Server Provisioning Script${NC}"
echo    "  ----------------------------------------"
echo

# ============================================================
# PREFLIGHT CHECKS
# ============================================================
log_section "Preflight Checks"

# Check OS — must be Ubuntu
if [ -f /etc/os-release ]; then
    . /etc/os-release
    log_info "OS: $NAME $VERSION_ID"
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "This script is designed for Ubuntu only. Detected: $ID"
        exit 1
    fi
else
    log_error "Cannot detect OS — aborting"
    exit 1
fi

# Check internet connectivity
if ping -c 1 8.8.8.8 &>/dev/null; then
    log_success "Internet connectivity confirmed"
else
    log_error "No internet connectivity — aborting"
    exit 1
fi

# ============================================================
# SYSTEM UPDATE
# ============================================================
log_section "System Update"

log_info "Updating package lists..."
apt-get update -qq
log_success "Package lists updated"

log_info "Upgrading installed packages..."
apt-get upgrade -y -qq
log_success "Packages upgraded"

# ============================================================
# INSTALL DEPENDENCIES
# ============================================================
log_section "Installing Dependencies"

PACKAGES=(
    curl
    wget
    git
    vim
    htop
    unzip
    ca-certificates
    gnupg
    lsb-release
    apparmor-utils
    nfs-common
    python3-pip
    python3-venv
)

for pkg in "${PACKAGES[@]}"; do
    if dpkg -l "$pkg" &>/dev/null; then
        log_info "$pkg already installed — skipping"
    else
        log_info "Installing $pkg..."
        apt-get install -y -qq "$pkg"
        log_success "$pkg installed"
    fi
done

# ============================================================
# INSTALL DOCKER
# ============================================================
log_section "Docker Installation"

if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version)
    log_info "Docker already installed — $DOCKER_VERSION"
else
    log_info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    log_success "Docker GPG key added"

    log_info "Adding Docker repository..."
    tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    apt-get update -qq
    log_success "Docker repository added"

    log_info "Installing Docker packages..."
    apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin
    log_success "Docker installed"
fi

# Verify Docker Compose plugin
if docker compose version &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version)
    log_success "Docker Compose available — $COMPOSE_VERSION"
else
    log_error "Docker Compose plugin not found — check your Docker installation"
    exit 1
fi

# Create docker group if it doesn't exist
if ! getent group docker &>/dev/null; then
    groupadd docker
    log_success "Created docker group"
else
    log_info "docker group already exists — skipping"
fi

# Add the invoking user to the docker group
if [ -n "${SUDO_USER:-}" ]; then
    usermod -aG docker "$SUDO_USER"
    log_success "Added $SUDO_USER to docker group"
    log_warn "User must log out and back in for group change to take effect"
fi

# Enable Docker and containerd services
systemctl enable docker.service
systemctl enable containerd.service
systemctl start docker
log_success "Docker and containerd services enabled and started"

# ============================================================
# DOCKER + FIREWALL CONFIGURATION
# ============================================================
# IMPORTANT: UFW and Docker are incompatible when used together.
# Docker manipulates iptables directly in the nat table, which
# means published container ports bypass UFW rules entirely.
#
# Strategy: We do NOT use UFW. Docker manages iptables directly.
# Security is enforced by:
#   1. Binding all container ports to 127.0.0.1 via daemon.json
#   2. Only Traefik binds to 0.0.0.0 on ports 80 and 443
#   3. All inter-VLAN security handled by UDM-Pro-Max firewall
# ============================================================
log_section "Firewall Configuration"

log_warn "UFW is NOT being enabled — Docker bypasses UFW via iptables nat table"
log_info "Configuring Docker daemon to prevent unintended port exposure..."

DAEMON_JSON="/etc/docker/daemon.json"

if [ -f "$DAEMON_JSON" ]; then
    log_warn "$DAEMON_JSON already exists — skipping to avoid overwriting customizations"
    log_warn "Manually ensure it contains: \"ip\": \"127.0.0.1\""
else
    cat > "$DAEMON_JSON" <<EOF
{
  "ip": "127.0.0.1",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    log_success "Docker daemon configured — ports bound to 127.0.0.1 by default"
fi

# Restart Docker to apply daemon.json
systemctl restart docker
log_success "Docker restarted with new daemon config"

# ============================================================
# LOAD ENVIRONMENT
# ============================================================
log_section "Loading Environment"

if [ -f ".env" ]; then
    DOCKER_DATA_PATH=$(grep -E '^DOCKER_DATA_PATH=' .env | cut -d= -f2 || true)
    MEDIA_PATH=$(grep -E '^MEDIA_PATH=' .env | cut -d= -f2 || true)
    PUID=$(grep -E '^PUID=' .env | cut -d= -f2 || true)
    PGID=$(grep -E '^PGID=' .env | cut -d= -f2 || true)
    log_info "Loaded path config from .env"
else
    log_warn ".env not found — using default paths (fill in .env and re-run if needed)"
fi

DOCKER_DATA_PATH=${DOCKER_DATA_PATH:-/media/arr/config}
MEDIA_PATH=${MEDIA_PATH:-/media/arr}
PUID=${PUID:-1000}
PGID=${PGID:-1000}

# ============================================================
# CREATE DIRECTORY STRUCTURE
# ============================================================
log_section "Creating Directory Structure"

DIRS=(
    # ------- Traefik -------
    "$DOCKER_DATA_PATH/traefik/certs"
    "$DOCKER_DATA_PATH/traefik/logs"

    # ------- Cloudflared -------
    "$DOCKER_DATA_PATH/cloudflared"

    # ------- WordPress / Webserver -------
    "$DOCKER_DATA_PATH/wordpress/html"
    "$DOCKER_DATA_PATH/wordpress/db"

    # ------- Authentik -------
    "$DOCKER_DATA_PATH/authentik/postgres"
    "$DOCKER_DATA_PATH/authentik/media"
    "$DOCKER_DATA_PATH/authentik/templates"
    "$DOCKER_DATA_PATH/authentik/certs"

    # ------- NetBox -------
    "$DOCKER_DATA_PATH/netbox/postgres"
    "$DOCKER_DATA_PATH/netbox/redis"
    "$DOCKER_DATA_PATH/netbox/media"
    "$DOCKER_DATA_PATH/netbox/reports"
    "$DOCKER_DATA_PATH/netbox/scripts"

    # ------- ARR Stack + Gluetun VPN -------
    "$DOCKER_DATA_PATH/gluetun"
    "$DOCKER_DATA_PATH/qbittorrent"
    "$DOCKER_DATA_PATH/radarr"
    "$DOCKER_DATA_PATH/radarr-4k"
    "$DOCKER_DATA_PATH/sonarr"
    "$DOCKER_DATA_PATH/sonarr-4k"
    "$DOCKER_DATA_PATH/lidarr"
    "$DOCKER_DATA_PATH/prowlarr"
    "$DOCKER_DATA_PATH/bazarr"
    "$DOCKER_DATA_PATH/recyclarr"

    # ------- Jellyfin Stack -------
    "$DOCKER_DATA_PATH/jellyfin"
    "$DOCKER_DATA_PATH/jellyseerr"
    "$DOCKER_DATA_PATH/jellystat"
    "$DOCKER_DATA_PATH/jellystat/db"
    "$DOCKER_DATA_PATH/jellystat/backup-data"

    # ------- Uptime Kuma -------
    "$DOCKER_DATA_PATH/uptime-kuma"

    # ------- Stirling PDF -------
    "$DOCKER_DATA_PATH/stirling-pdf/configs"
    "$DOCKER_DATA_PATH/stirling-pdf/logs"

    # ------- Paperless-ngx -------
    "$DOCKER_DATA_PATH/paperless/db"
    "$DOCKER_DATA_PATH/paperless/redis"
    "$DOCKER_DATA_PATH/paperless/data"
    "$DOCKER_DATA_PATH/paperless/media"
    "$MEDIA_PATH/paperless/consume"
    "$MEDIA_PATH/paperless/export"

    # ------- Immich -------
    "$DOCKER_DATA_PATH/immich/db"
    "$DOCKER_DATA_PATH/immich/ml-cache"
    "$MEDIA_PATH/immich/library"
    "$MEDIA_PATH/immich/upload"
    "$MEDIA_PATH/immich/thumbs"
    "$MEDIA_PATH/immich/profile"
    "$MEDIA_PATH/immich/video"

    # ------- Ntfy -------
    "$DOCKER_DATA_PATH/ntfy"

    # ------- Homebox -------
    "$DOCKER_DATA_PATH/homebox"

    # ------- Grocy -------
    "$DOCKER_DATA_PATH/grocy"

    # ------- Mealie -------
    "$DOCKER_DATA_PATH/mealie/db"
    "$DOCKER_DATA_PATH/mealie/data"

    # ------- Actual Budget -------
    "$DOCKER_DATA_PATH/actual"

    # ------- Media libraries (existing folders — do not overwrite) -------
    "$MEDIA_PATH/downloads/incomplete"
    "$MEDIA_PATH/downloads/complete/radarr"
    "$MEDIA_PATH/downloads/complete/radarr-4k"
    "$MEDIA_PATH/downloads/complete/sonarr"
    "$MEDIA_PATH/downloads/complete/sonarr-4k"
    "$MEDIA_PATH/downloads/complete/lidarr"
    "$MEDIA_PATH/downloads/complete/manual"
)

for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        log_info "$dir already exists — skipping"
    else
        mkdir -p "$dir"
        log_success "Created $dir"
    fi
done

# ============================================================
# SET PERMISSIONS
# ============================================================
log_section "Setting Permissions"

chown -R "$PUID:$PGID" "$DOCKER_DATA_PATH"
log_success "Set ownership on $DOCKER_DATA_PATH to $PUID:$PGID"

chown -R "$PUID:$PGID" "$MEDIA_PATH"
log_success "Set ownership on $MEDIA_PATH to $PUID:$PGID"

# Traefik requires acme.json to be exactly 600 or it refuses to start
ACME_FILE="$DOCKER_DATA_PATH/traefik/certs/acme.json"
touch "$ACME_FILE"
chmod 600 "$ACME_FILE"
log_success "Created and locked down acme.json (600)"

# ============================================================
# COPY .ENV FILES
# ============================================================
log_section "Setting Up Environment Files"

find . -name ".env.example" | while read -r f; do
    target="${f/.env.example/.env}"
    if [ ! -f "$target" ]; then
        cp "$f" "$target"
        log_success "Created $target"
    else
        log_info "Skipping $target — already exists"
    fi
done

# ============================================================
# DOCKER NETWORKS
# ============================================================
log_section "Creating Docker Networks"

declare -A NETWORKS=(
    ["proxy"]="Traefik reverse proxy — all externally routed services"
    ["wordpress-internal"]="WordPress ↔ MariaDB isolation"
    ["authentik-internal"]="Authentik ↔ PostgreSQL isolation"
    ["netbox-internal"]="NetBox ↔ PostgreSQL + Redis isolation"
    ["arr-stack"]="Internal ARR stack communication"
    ["media-internal"]="Jellyfin, Jellyseerr, ARR apps"
    ["paperless-internal"]="Paperless ↔ PostgreSQL + Redis isolation"
    ["immich-internal"]="Immich ↔ PostgreSQL + Redis + ML isolation"
    ["mealie-internal"]="Mealie ↔ PostgreSQL isolation"
    ["monitoring"]="Reserved — future metrics/monitoring"
)

for network in "${!NETWORKS[@]}"; do
    if docker network inspect "$network" &>/dev/null; then
        log_info "Network '$network' already exists — skipping"
    else
        docker network create "$network"
        log_success "Created Docker network: $network (${NETWORKS[$network]})"
    fi
done

# ============================================================
# BUILD CUSTOM IMAGES
# ============================================================
log_section "Building Custom Docker Images"

# NetBox requires a custom image with netbox_unifi_sync plugin
if [ -f "docker/netbox/Dockerfile" ]; then
    log_info "Building NetBox custom image (eirdom/netbox:v4.5)..."
    if docker compose -f docker/netbox/docker-compose.yml build 2>/dev/null; then
        log_success "NetBox custom image built successfully"
    else
        log_warn "NetBox image build failed — review docker/netbox/Dockerfile"
    fi
else
    log_warn "docker/netbox/Dockerfile not found — skipping NetBox image build"
fi

# ============================================================
# VALIDATE DOCKER COMPOSE FILES
# ============================================================
log_section "Validating Docker Compose Files"

COMPOSE_FILES=(
    "docker/traefik/docker-compose.yml"
    "docker/authentik/docker-compose.yml"
    "docker/cloudflared/docker-compose.yml"
    "docker/webserver/docker-compose.yml"
    "docker/arr-stack/docker-compose.yml"
    "docker/jellyfin/docker-compose.yml"
    "docker/netbox/docker-compose.yml"
    "docker/uptime-kuma/docker-compose.yml"
    "docker/stirling-pdf/docker-compose.yml"
    "docker/paperless/docker-compose.yml"
    "docker/immich/docker-compose.yml"
    "docker/ntfy/docker-compose.yml"
    "docker/homebox/docker-compose.yml"
    "docker/grocy/docker-compose.yml"
    "docker/mealie/docker-compose.yml"
    "docker/actual/docker-compose.yml"
)

ALL_VALID=true

for compose in "${COMPOSE_FILES[@]}"; do
    if [ -f "$compose" ]; then
        if docker compose -f "$compose" config --quiet 2>/dev/null; then
            log_success "$compose is valid"
        else
            log_warn "$compose has errors — review before starting"
            ALL_VALID=false
        fi
    else
        log_warn "$compose not found — skipping validation"
    fi
done

if [ "$ALL_VALID" = false ]; then
    log_warn "Some compose files have issues — fix before deploying"
fi

# ============================================================
# SUMMARY
# ============================================================
log_section "Provisioning Complete"

echo
echo -e "${BOLD}  Next Steps:${NC}"
echo    "  ----------------------------------------"
echo    "  1. Fill in ALL .env files before starting any service"
echo    "  2. Start services in this exact order:"
echo    ""
echo    "       → Traefik       cd docker/traefik       && docker compose up -d"
echo    "       → Authentik     cd docker/authentik     && docker compose up -d"
echo    "       → Cloudflared   cd docker/cloudflared   && docker compose up -d"
echo    "       → Webserver     cd docker/webserver     && docker compose up -d"
echo    "       → ARR Stack     cd docker/arr-stack     && docker compose up -d"
echo    "       → Jellyfin      cd docker/jellyfin      && docker compose up -d"
echo    "       → NetBox        cd docker/netbox        && docker compose up -d"
echo    "       → Uptime Kuma   cd docker/uptime-kuma   && docker compose up -d"
echo    "       → Stirling PDF  cd docker/stirling-pdf  && docker compose up -d"
echo    "       → Paperless     cd docker/paperless     && docker compose up -d"
echo    "       → Immich        cd docker/immich        && docker compose up -d"
echo    "       → Ntfy          cd docker/ntfy          && docker compose up -d"
echo    "       → Homebox       cd docker/homebox       && docker compose up -d"
echo    "       → Grocy         cd docker/grocy         && docker compose up -d"
echo    "       → Mealie        cd docker/mealie        && docker compose up -d"
echo    "       → Actual Budget cd docker/actual        && docker compose up -d"
echo    ""
echo    "  3. After Authentik is running:"
echo    "       → Complete initial Authentik setup at https://auth.eirdom.homes/if/flow/initial-setup/"
echo    "       → Configure Traefik ForwardAuth provider"
echo    "       → Configure AD LDAP source"
echo    ""
echo    "  4. After NetBox is running:"
echo    "       → Run first UniFi sync dry-run"
echo    "       → Import Ubiquiti device types from community library"
echo    "       → Configure scheduled sync"
echo    ""
echo    "  5. Verify Traefik wildcard cert issued:"
echo    "       → cat ${DOCKER_DATA_PATH}/traefik/certs/acme.json | python3 -m json.tool | grep -c certificate"
echo    ""
echo -e "  ${YELLOW}Firewall reminder:${NC}"
echo    "  UFW is NOT active. Security enforced by:"
echo    "    - Docker daemon bound to 127.0.0.1"
echo    "    - Only Traefik binds to 0.0.0.0 on 80/443"
echo    "    - UDM-Pro-Max zone firewall handles inter-VLAN rules"
echo
if [ -n "${SUDO_USER:-}" ]; then
    echo -e "  ${YELLOW}Remember:${NC} Log out and back in as $SUDO_USER for Docker group changes"
    echo
fi
echo -e "  ${GREEN}Eirdom is ready for deployment.${NC}"
echo