#!/usr/bin/env bash
# =============================================================================
# repo-install.sh — Arch Linux Bootstrap Installer
# Fetches package lists from GitHub and installs via pacman + yay
# =============================================================================

set -euo pipefail

# --- Config ------------------------------------------------------------------
GITHUB_RAW="https://raw.githubusercontent.com/jerryjay45/My-packagelist/main"
PACMAN_LIST_URL="$GITHUB_RAW/package-pacman.txt"
AUR_LIST_URL="$GITHUB_RAW/aur-packages.txt"

PACMAN_FAILED_LOG="pacman-failed.txt"
AUR_FAILED_LOG="aur-failed.txt"

# --- Colors ------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# --- Helpers -----------------------------------------------------------------
info()    { echo -e "${CYAN}${BOLD}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}${BOLD}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}${BOLD}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}${BOLD}[ERROR]${RESET} $*" >&2; }
step()    { echo -e "\n${BOLD}==============================${RESET}\n${BOLD}$*${RESET}\n${BOLD}==============================${RESET}"; }

# --- Preflight ---------------------------------------------------------------
step "Preflight Checks"

if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root. It will use sudo where needed."
    exit 1
fi

for cmd in curl sudo pacman; do
    if ! command -v "$cmd" &>/dev/null; then
        error "Required command not found: $cmd"
        exit 1
    fi
done
success "Running as $(whoami), sudo and curl available."

# --- Step 1: System update ---------------------------------------------------
step "Step 1: Updating System"
sudo pacman -Syu --noconfirm
success "System updated."

# --- Step 2: Install yay if missing ------------------------------------------
step "Step 2: Installing Prerequisites"

if ! command -v yay &>/dev/null; then
    info "yay not found — installing from AUR..."
    sudo pacman -S --needed --noconfirm git base-devel
    TMPDIR=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$TMPDIR/yay"
    (cd "$TMPDIR/yay" && makepkg -si --noconfirm)
    rm -rf "$TMPDIR"
    success "yay installed."
else
    success "yay already installed: $(yay --version | head -1)"
fi

# --- Step 3: Configure CachyOS repos ----------------------------------------
step "Step 3: Configuring CachyOS Repositories"

if ! grep -q "\[cachyos\]" /etc/pacman.conf 2>/dev/null; then
    info "Adding CachyOS repositories..."
    sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key F3B607488DB35A47
    sudo pacman -U --noconfirm \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-18-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-18-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-6-1-any.pkg.tar.zst' \
        'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-6.1.0-7-x86_64.pkg.tar.zst'

    cat <<'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
    sudo pacman -Sy
    success "CachyOS repositories added."
else
    warn "CachyOS repositories already present — skipping."
fi

# --- Step 4: Configure Chaotic-AUR -------------------------------------------
step "Step 4: Configuring Chaotic-AUR Repositories"

if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf 2>/dev/null; then
    info "Adding Chaotic-AUR repository..."
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

    cat <<'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
    sudo pacman -Sy
    success "Chaotic-AUR repository added."
else
    warn "Chaotic-AUR already present — skipping."
fi

# --- Step 5: Fetch package lists ---------------------------------------------
step "Step 5: Fetching Package Lists from GitHub"

info "Fetching pacman list from: $PACMAN_LIST_URL"
PACMAN_PACKAGES=$(curl -fsSL "$PACMAN_LIST_URL" | grep -v '^\s*#' | grep -v '^\s*$')
PACMAN_COUNT=$(echo "$PACMAN_PACKAGES" | wc -l)
success "Fetched $PACMAN_COUNT pacman packages."

info "Fetching AUR list from: $AUR_LIST_URL"
AUR_PACKAGES=$(curl -fsSL "$AUR_LIST_URL" | grep -v '^\s*#' | grep -v '^\s*$')
AUR_COUNT=$(echo "$AUR_PACKAGES" | wc -l)
success "Fetched $AUR_COUNT AUR packages."

# Clear old logs
> "$PACMAN_FAILED_LOG"
> "$AUR_FAILED_LOG"

# --- Step 6: Install pacman packages -----------------------------------------
step "Step 6: Installing Pacman Packages ($PACMAN_COUNT total)"

PACMAN_INSTALLED=0
PACMAN_FAILED=0

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if sudo pacman -S --needed --noconfirm "$pkg" &>/dev/null; then
        PACMAN_INSTALLED=$((PACMAN_INSTALLED + 1))
    else
        warn "pacman: failed to install '$pkg'"
        echo "$pkg" >> "$PACMAN_FAILED_LOG"
        PACMAN_FAILED=$((PACMAN_FAILED + 1))
    fi
done <<< "$PACMAN_PACKAGES"

success "Pacman: $PACMAN_INSTALLED installed, $PACMAN_FAILED failed."
[[ $PACMAN_FAILED -gt 0 ]] && warn "Failed packages logged to: $PACMAN_FAILED_LOG"

# --- Step 7: Install AUR packages --------------------------------------------
step "Step 7: Installing AUR Packages ($AUR_COUNT total)"

AUR_INSTALLED=0
AUR_FAILED=0

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if yay -S --needed --noconfirm "$pkg" &>/dev/null; then
        AUR_INSTALLED=$((AUR_INSTALLED + 1))
    else
        warn "yay: failed to install '$pkg'"
        echo "$pkg" >> "$AUR_FAILED_LOG"
        AUR_FAILED=$((AUR_FAILED + 1))
    fi
done <<< "$AUR_PACKAGES"

success "AUR: $AUR_INSTALLED installed, $AUR_FAILED failed."
[[ $AUR_FAILED -gt 0 ]] && warn "Failed packages logged to: $AUR_FAILED_LOG"

# --- Summary -----------------------------------------------------------------
step "Installation Complete"

echo -e "  ${GREEN}Pacman:${RESET} $PACMAN_INSTALLED installed  |  ${RED}$PACMAN_FAILED failed${RESET}"
echo -e "  ${GREEN}AUR:${RESET}    $AUR_INSTALLED installed  |  ${RED}$AUR_FAILED failed${RESET}"

if [[ -s "$PACMAN_FAILED_LOG" ]] || [[ -s "$AUR_FAILED_LOG" ]]; then
    echo ""
    warn "Some packages failed. Review the logs:"
    [[ -s "$PACMAN_FAILED_LOG" ]] && echo "  → $PACMAN_FAILED_LOG"
    [[ -s "$AUR_FAILED_LOG"   ]] && echo "  → $AUR_FAILED_LOG"
fi

echo ""
success "Done! You may want to reboot: sudo reboot"
