#!/usr/bin/env bash
# install.sh — macOS zero-to-hero Paperclip bootstrap
# Idempotent: safe to run more than once.
set -euo pipefail

# ─── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

log_step()  { echo -e "
${BOLD}${BLUE}▶ $*${RESET}"; }
log_ok()    { echo -e "  ${GREEN}✔ $*${RESET}"; }
log_info()  { echo -e "  ${YELLOW}ℹ $*${RESET}"; }
log_error() { echo -e "
${RED}✖ ERROR: $*${RESET}" >&2; }

die() { log_error "$*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Step 1/9: System check ────────────────────────────────────────────────────
log_step "Step 1/9 — Checking system"

[[ "$(uname)" == "Darwin" ]] || die "This script only runs on macOS."

MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
ARCH=$(uname -m)   # arm64 or x86_64

[[ "$MACOS_MAJOR" -ge 12 ]] || \
  die "Paperclip requires macOS 12 (Monterey) or later. You have $MACOS_VERSION."

if [[ "$ARCH" == "arm64" ]]; then
    ARCH_LABEL="Apple Silicon (arm64)"
else
    ARCH_LABEL="Intel (x86_64)"
fi
log_ok "macOS $MACOS_VERSION on $ARCH_LABEL"

# ─── Step 2/9: Docker Desktop ──────────────────────────────────────────────────
log_step "Step 2/9 — Docker Desktop"

if docker info &>/dev/null; then
    log_ok "Docker daemon already running — skipping install"
else
    if [[ ! -d /Applications/Docker.app ]]; then
        if [[ "$ARCH" == "arm64" ]]; then
            DMG_URL="https://desktop.docker.com/mac/main/arm64/Docker.dmg"
        else
            DMG_URL="https://desktop.docker.com/mac/main/amd64/Docker.dmg"
        fi
        log_info "Downloading Docker Desktop for $ARCH_LABEL…"
        DOCKER_TMP=$(mktemp -d)
        DMG_PATH="$DOCKER_TMP/Docker.dmg"
        curl -fL --progress-bar "$DMG_URL" -o "$DMG_PATH" \
          || die "Failed to download Docker Desktop. Check your internet connection."

        log_info "Installing Docker Desktop…"
        MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -noautoopen 2>/dev/null \
                      | awk '/\/Volumes/{print $NF}')
        cp -R "$MOUNT_POINT/Docker.app" /Applications/
        hdiutil detach "$MOUNT_POINT" -quiet
        rm -rf "$DOCKER_TMP"
        log_ok "Docker Desktop installed"
    else
        log_info "Docker Desktop found in /Applications — launching…"
    fi

    open /Applications/Docker.app
    log_info "Waiting for Docker daemon to start (up to 120 s)…"
    ELAPSED=0
    until docker info &>/dev/null; do
        [[ "$ELAPSED" -ge 120 ]] && \
          die "Docker daemon did not start within 120 s. Try opening Docker Desktop manually."
        sleep 3; ELAPSED=$((ELAPSED + 3)); printf "."
    done
    echo ""
    log_ok "Docker daemon is ready"
fi

# ─── Step 3/9: Node.js via nvm ─────────────────────────────────────────────────
log_step "Step 3/9 — Node.js (via nvm)"

NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    log_info "Installing nvm…"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
      || die "Failed to install nvm."
    log_ok "nvm installed"
fi

# shellcheck source=/dev/null
source "$NVM_DIR/nvm.sh"

if ! node --version &>/dev/null; then
    log_info "Installing Node.js LTS…"
    nvm install --lts || die "Failed to install Node.js LTS."
    nvm use --lts
    log_ok "Node.js $(node --version) installed"
else
    log_ok "Node.js $(node --version) already available"
fi

# ─── Step 4/9: Claude Code CLI ─────────────────────────────────────────────────
log_step "Step 4/9 — Claude Code CLI"

if command -v claude &>/dev/null; then
    log_ok "Claude Code CLI already installed"
else
    log_info "Installing @anthropic-ai/claude-code globally…"
    npm install -g @anthropic-ai/claude-code \
      || die "Failed to install Claude Code CLI. Ensure npm is working correctly."
    log_ok "Claude Code CLI installed"
fi

# ─── Step 5/9: Claude authentication ──────────────────────────────────────────
log_step "Step 5/9 — Claude authentication"

# claude auth status exits 0 when authenticated
if claude auth status &>/dev/null; then
    log_ok "Already authenticated with Claude"
else
    log_info "A browser window will open — sign in with your Claude Max account."
    claude auth login || die "Claude authentication failed. Please re-run this script."
    log_ok "Claude authenticated"
fi

# ─── Step 6/9: Network exposure ────────────────────────────────────────────────
log_step "Step 6/9 — Phone-accessible network exposure"

ACCESS_URL=""

if [[ -n "${PAPERCLIP_SKIP_NETWORK:-}" ]]; then
    log_info "Skipping network setup (PAPERCLIP_SKIP_NETWORK is set) — Paperclip will be accessible on localhost only"
elif [[ -d /Applications/NordVPN.app ]] || command -v nordvpn &>/dev/null; then
    # ── NordVPN Meshnet path ──────────────────────────────────────────────────
    log_info "NordVPN detected — enabling Meshnet…"
    nordvpn set meshnet on \
      || die "Failed to enable NordVPN Meshnet. Make sure NordVPN is running and you are logged in."

    # Prefer the authoritative .nord hostname from the NordVPN daemon; fall back to a derived guess.
    NORD_HOST=$(nordvpn meshnet peer list --self 2>/dev/null \
        | grep -i 'Hostname' | awk '{print $NF}' | sed 's/\.nord$//' | head -1)
    if [[ -z "$NORD_HOST" ]]; then
        NORD_HOST=$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')
    fi
    ACCESS_URL="http://${NORD_HOST}.nord:3100"
    log_ok "NordVPN Meshnet enabled"

    echo ""
    echo -e "  ${BOLD}📱 Phone access — NordVPN Meshnet${RESET}"
    echo -e "  URL: ${BOLD}${ACCESS_URL}${RESET}"
    echo    "  On your phone:"
    echo    "    1. Install NordVPN"
    echo    "    2. Enable Meshnet in the NordVPN app settings"
    echo    "    3. Open ${ACCESS_URL} in your phone browser"

else
    # ── Tailscale Funnel path ─────────────────────────────────────────────────
    log_info "NordVPN not found — using Tailscale Funnel…"

    if ! command -v tailscale &>/dev/null; then
        log_info "Installing Tailscale…"
        curl -fsSL https://tailscale.com/install.sh | sh \
          || die "Failed to install Tailscale."
        log_ok "Tailscale installed"
    else
        log_ok "Tailscale already installed"
    fi

    if ! tailscale status &>/dev/null; then
        log_info "Connecting Tailscale (a browser login may open)…"
        sudo tailscale up || die "Failed to bring up Tailscale."
    else
        log_ok "Tailscale already connected"
    fi

    log_info "Enabling Tailscale Funnel on port 3100…"
    sudo tailscale funnel 3100 \
      || die "Failed to enable Tailscale Funnel. Ensure your Tailscale plan supports Funnel."

    # Resolve the public HTTPS URL from tailscale status
    TS_DNS=$(tailscale status --json 2>/dev/null \
      | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Self',{}).get('DNSName','').rstrip('.'))" \
      2>/dev/null || true)

    if [[ -n "$TS_DNS" ]]; then
        ACCESS_URL="https://${TS_DNS}"
    else
        ACCESS_URL="https://<your-tailscale-hostname>  (run: tailscale status)"
    fi

    log_ok "Tailscale Funnel active"

    echo ""
    echo -e "  ${BOLD}📱 Phone access — Tailscale Funnel${RESET}"
    echo -e "  URL: ${BOLD}${ACCESS_URL}${RESET}"
    echo    "  On your phone:"
    echo    "    • No app needed — open the URL in any browser"
fi

# ─── Step 7/9: ~/paperclip/ directory and .env ─────────────────────────────────
log_step "Step 7/9 — Paperclip data directory and configuration"

PAPERCLIP_DIR="$HOME/paperclip"
mkdir -p "$PAPERCLIP_DIR/db" "$PAPERCLIP_DIR/storage" "$PAPERCLIP_DIR/secrets" "$PAPERCLIP_DIR/projects"
log_ok "Directory tree at $PAPERCLIP_DIR"

ENV_FILE="$PAPERCLIP_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    log_ok ".env already exists — preserving existing config (delete to regenerate)"
else
    JWT_SECRET=$(openssl rand -hex 32)
    PUBLIC_URL="${ACCESS_URL:-http://localhost:3100}"
    cat > "$ENV_FILE" <<EOF
PAPERCLIP_PORT=3100
BETTER_AUTH_SECRET=${JWT_SECRET}
PAPERCLIP_PUBLIC_URL=${PUBLIC_URL}
HOST=0.0.0.0
PORT=3100
PAPERCLIP_HOME=/paperclip
PAPERCLIP_DEPLOYMENT_MODE=authenticated
PAPERCLIP_DEPLOYMENT_EXPOSURE=private
EOF
    log_ok ".env written with auto-generated secret"
fi

# Copy or write docker-compose.yml
COMPOSE_DST="$PAPERCLIP_DIR/docker-compose.yml"
if [[ -f "$COMPOSE_DST" ]]; then
    log_ok "docker-compose.yml already present"
elif [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    cp "$SCRIPT_DIR/docker-compose.yml" "$COMPOSE_DST"
    log_ok "docker-compose.yml copied from installer package"
else
    # Embedded fallback — keeps install.sh self-contained
    cat > "$COMPOSE_DST" <<'COMPOSE'
services:
  paperclip:
    image: ghcr.io/paperclipai/paperclip:latest
    ports:
      - "${PAPERCLIP_PORT:-3100}:3100"
    volumes:
      - .:/paperclip
    env_file: .env
    restart: unless-stopped
COMPOSE
    log_ok "docker-compose.yml written (embedded fallback)"
fi

# ─── Step 8/9: Start Paperclip ────────────────────────────────────────────────
log_step "Step 8/9 — Starting Paperclip"

cd "$PAPERCLIP_DIR"
docker compose up -d \
  || die "Failed to start Paperclip. Run 'docker compose logs' in $PAPERCLIP_DIR for details."
log_ok "Paperclip containers started"

log_info "Waiting for Paperclip to respond on port 3100…"
for i in {1..20}; do
    if curl -sf "http://localhost:3100/health" &>/dev/null; then
        log_ok "Paperclip is up and healthy"
        break
    fi
    sleep 2
    [[ "$i" -eq 20 ]] && die "Paperclip did not respond on port 3100 after 40 s. Run 'docker compose logs' in $PAPERCLIP_DIR for details."
done

# ─── Step 9/9: Summary ────────────────────────────────────────────────────────
log_step "Step 9/9 — All done!"

echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  🎉  Paperclip is installed and running                      ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${BOLD}Access URL (phone / remote):${RESET}  ${ACCESS_URL}"
echo -e "  ${BOLD}Local URL:${RESET}                    http://localhost:3100"
echo -e "  ${BOLD}Data directory:${RESET}               $PAPERCLIP_DIR"
echo ""
echo -e "  ${BOLD}Commands:${RESET}"
echo -e "    Start:   cd $PAPERCLIP_DIR && docker compose up -d"
echo -e "    Stop:    cd $PAPERCLIP_DIR && docker compose down"
echo -e "    Logs:    cd $PAPERCLIP_DIR && docker compose logs -f"
echo -e "    Update:  cd $PAPERCLIP_DIR && docker compose pull && docker compose up -d"
echo ""
