#!/bin/bash

# ============================================================
# repo-install.sh - Jerry's Arch Linux Package Installer
# Inspired by JaKooLit's Hyprland-v4 install style
# ============================================================

# Do not run as root
if [[ $EUID -eq 0 ]]; then
    echo "This script should not be executed as root! Exiting......."
    exit 1
fi

clear

# --- Colors (tput style, like JaKooLit) ---
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
WARN="$(tput setaf 166)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
RESET=$(tput sgr0)

# --- ASCII Banner ---
display_banner() {
cat << "EOF"

  __  __           _                    _
 |  \/  | ___ _ __| |__   __ _ _ __ | |_
 | |\/| |/ _ \ '__| '_ \ / _` | '_ \| __|
 | |  | |  __/ |  | | | | (_| | | | | |_
 |_|  |_|\___|_|  |_| |_|\__,_|_| |_|\__|

  ____   ___  ____    ___           _        _ _
 |  _ \ / _ \/ ___|  |_ _|_ __  ___| |_ __ _| | | ___ _ __
 | |_) | | | \___ \   | || '_ \/ __| __/ _` | | |/ _ \ '__|
 |  __/| |_| |___) |  | || | | \__ \ || (_| | | |  __/ |
 |_|    \___/|____/  |___|_| |_|___/\__\__,_|_|_|\___|_|

EOF
}

display_banner

# --- Log file ---
LOG="install-$(date +%d-%H%M%S).log"
echo "Install log: $LOG"
echo ""

# --- GitHub URLs ---
GITHUB_RAW="https://raw.githubusercontent.com/jerryjay45/My-packagelist/main"
PACMAN_LIST_URL="$GITHUB_RAW/package-pacman.txt"
AUR_LIST_URL="$GITHUB_RAW/aur-packages.txt"

PACMAN_FAILED_LOG="pacman-failed.txt"
AUR_FAILED_LOG="aur-failed.txt"

# --- Helper functions (JaKooLit style) ---
colorize_prompt() {
    local color="$1"
    local message="$2"
    echo -n "${color}${message}$(tput sgr0)"
}

ask_yes_no() {
    while true; do
        read -p "$(colorize_prompt "$CAT" "$1 (y/n): ")" choice
        case "$choice" in
            [Yy]* ) eval "$2='Y'"; return 0 ;;
            [Nn]* ) eval "$2='N'"; return 1 ;;
            * ) echo "Please answer with y or n." ;;
        esac
    done
}

# --- Welcome ---
echo "$(tput setaf 6)Welcome to Jerry's Arch Linux POS Installer!$(tput sgr0)"
echo ""
echo "${NOTE} This script will:"
echo "  1. Update your system"
echo "  2. Set up CachyOS + Chaotic-AUR repositories"
echo "  3. Install yay (if not present)"
echo "  4. Install all packages from your GitHub package lists"
echo ""
read -p "$(colorize_prompt "$CAT" "Would you like to proceed? (y/n): ")" proceed
if [[ "$proceed" != "y" && "$proceed" != "Y" ]]; then
    echo "Installation aborted."
    exit 1
fi

# --- Ask optional steps ---
printf "\n"
ask_yes_no "Set up CachyOS repositories?" setup_cachyos
printf "\n"
ask_yes_no "Set up Chaotic-AUR repository?" setup_chaotic
printf "\n"
ask_yes_no "Install yay if not already installed?" install_yay
printf "\n"

# ============================================================
# STEP 1 - System Update
# ============================================================
echo ""
echo "${INFO} Updating system..." | tee -a "$LOG"
sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOG"
echo "${OK} System updated." | tee -a "$LOG"
sleep 1

# ============================================================
# STEP 2 - Install yay
# ============================================================
if [[ "$install_yay" == "Y" ]]; then
    if ! command -v yay &>/dev/null; then
        echo ""
        echo "${INFO} Installing yay AUR helper..." | tee -a "$LOG"
        sudo pacman -S --needed --noconfirm git base-devel 2>&1 | tee -a "$LOG"
        TMPDIR=$(mktemp -d)
        git clone https://aur.archlinux.org/yay.git "$TMPDIR/yay" 2>&1 | tee -a "$LOG"
        (cd "$TMPDIR/yay" && makepkg -si --noconfirm 2>&1 | tee -a "$LOG")
        rm -rf "$TMPDIR"
        echo "${OK} yay installed." | tee -a "$LOG"
    else
        echo "${OK} yay is already installed: $(yay --version | head -1)" | tee -a "$LOG"
    fi
fi
sleep 1

# ============================================================
# STEP 3 - CachyOS Repositories
# ============================================================
if [[ "$setup_cachyos" == "Y" ]]; then
    echo ""
    echo "${INFO} Setting up CachyOS repositories..." | tee -a "$LOG"
    if grep -q "\[cachyos\]" /etc/pacman.conf 2>/dev/null; then
        echo "${WARN} CachyOS repositories already present — skipping." | tee -a "$LOG"
    else
        sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com 2>&1 | tee -a "$LOG"
        sudo pacman-key --lsign-key F3B607488DB35A47 2>&1 | tee -a "$LOG"
        sudo pacman -U --noconfirm \
            'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' \
            'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-18-1-any.pkg.tar.zst' \
            'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v3-mirrorlist-18-1-any.pkg.tar.zst' \
            'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-v4-mirrorlist-6-1-any.pkg.tar.zst' \
            'https://mirror.cachyos.org/repo/x86_64/cachyos/pacman-6.1.0-7-x86_64.pkg.tar.zst' 2>&1 | tee -a "$LOG"

        cat <<'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
        sudo pacman -Sy 2>&1 | tee -a "$LOG"
        echo "${OK} CachyOS repositories added." | tee -a "$LOG"
    fi
fi
sleep 1

# ============================================================
# STEP 4 - Chaotic-AUR Repository
# ============================================================
if [[ "$setup_chaotic" == "Y" ]]; then
    echo ""
    echo "${INFO} Setting up Chaotic-AUR repository..." | tee -a "$LOG"
    if grep -q "\[chaotic-aur\]" /etc/pacman.conf 2>/dev/null; then
        echo "${WARN} Chaotic-AUR already present — skipping." | tee -a "$LOG"
    else
        sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com 2>&1 | tee -a "$LOG"
        sudo pacman-key --lsign-key 3056513887B78AEB 2>&1 | tee -a "$LOG"
        sudo pacman -U --noconfirm \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' 2>&1 | tee -a "$LOG"

        cat <<'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
        sudo pacman -Sy 2>&1 | tee -a "$LOG"
        echo "${OK} Chaotic-AUR repository added." | tee -a "$LOG"
    fi
fi
sleep 1

# ============================================================
# STEP 5 - Fetch Package Lists
# ============================================================
echo ""
echo "${INFO} Fetching package lists from GitHub..." | tee -a "$LOG"

PACMAN_PACKAGES=$(curl -fsSL "$PACMAN_LIST_URL" | grep -v '^\s*#' | grep -v '^\s*$')
if [[ -z "$PACMAN_PACKAGES" ]]; then
    echo "${ERROR} Failed to fetch pacman package list. Check your internet or repo URL." | tee -a "$LOG"
    exit 1
fi
PACMAN_COUNT=$(echo "$PACMAN_PACKAGES" | wc -l)
echo "${OK} Fetched $PACMAN_COUNT pacman packages." | tee -a "$LOG"

AUR_PACKAGES=$(curl -fsSL "$AUR_LIST_URL" | grep -v '^\s*#' | grep -v '^\s*$')
if [[ -z "$AUR_PACKAGES" ]]; then
    echo "${ERROR} Failed to fetch AUR package list. Check your internet or repo URL." | tee -a "$LOG"
    exit 1
fi
AUR_COUNT=$(echo "$AUR_PACKAGES" | wc -l)
echo "${OK} Fetched $AUR_COUNT AUR packages." | tee -a "$LOG"

> "$PACMAN_FAILED_LOG"
> "$AUR_FAILED_LOG"
sleep 1

# ============================================================
# STEP 6 - Install Pacman Packages
# ============================================================
echo ""
echo "${INFO} Installing pacman packages ($PACMAN_COUNT total)..." | tee -a "$LOG"

PACMAN_INSTALLED=0
PACMAN_FAILED=0

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    echo -n "${INFO} Installing ${CYAN}$pkg${RESET}... "
    if sudo pacman -S --needed --noconfirm "$pkg" >> "$LOG" 2>&1; then
        echo "${OK}"
        PACMAN_INSTALLED=$((PACMAN_INSTALLED + 1))
    else
        echo "${ERROR}"
        echo "$pkg" >> "$PACMAN_FAILED_LOG"
        PACMAN_FAILED=$((PACMAN_FAILED + 1))
    fi
done <<< "$PACMAN_PACKAGES"

echo ""
echo "${OK} Pacman: ${GREEN}$PACMAN_INSTALLED installed${RESET} | ${RED}$PACMAN_FAILED failed${RESET}" | tee -a "$LOG"
[[ $PACMAN_FAILED -gt 0 ]] && echo "${WARN} Failed packages logged to: $PACMAN_FAILED_LOG" | tee -a "$LOG"
sleep 1

# ============================================================
# STEP 7 - Install AUR Packages
# ============================================================
echo ""
echo "${INFO} Installing AUR packages ($AUR_COUNT total)..." | tee -a "$LOG"

AUR_INSTALLED=0
AUR_FAILED=0

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    echo -n "${INFO} Installing ${MAGENTA}$pkg${RESET} (AUR)... "
    if yay -S --needed --noconfirm "$pkg" >> "$LOG" 2>&1; then
        echo "${OK}"
        AUR_INSTALLED=$((AUR_INSTALLED + 1))
    else
        echo "${ERROR}"
        echo "$pkg" >> "$AUR_FAILED_LOG"
        AUR_FAILED=$((AUR_FAILED + 1))
    fi
done <<< "$AUR_PACKAGES"

echo ""
echo "${OK} AUR: ${GREEN}$AUR_INSTALLED installed${RESET} | ${RED}$AUR_FAILED failed${RESET}" | tee -a "$LOG"
[[ $AUR_FAILED -gt 0 ]] && echo "${WARN} Failed packages logged to: $AUR_FAILED_LOG" | tee -a "$LOG"

# ============================================================
# DONE
# ============================================================
clear
printf "\n${OK} ${GREEN}Yey! Installation Completed.${RESET}\n\n"

echo "  Pacman : ${GREEN}$PACMAN_INSTALLED installed${RESET}  |  ${RED}$PACMAN_FAILED failed${RESET}"
echo "  AUR    : ${GREEN}$AUR_INSTALLED installed${RESET}  |  ${RED}$AUR_FAILED failed${RESET}"
echo ""

if [[ -s "$PACMAN_FAILED_LOG" ]] || [[ -s "$AUR_FAILED_LOG" ]]; then
    echo "${WARN} Some packages failed to install. Review the logs:"
    [[ -s "$PACMAN_FAILED_LOG" ]] && echo "  → $PACMAN_FAILED_LOG"
    [[ -s "$AUR_FAILED_LOG"   ]] && echo "  → $AUR_FAILED_LOG"
    echo ""
fi

echo "${NOTE} Full install log saved to: ${YELLOW}$LOG${RESET}"
echo ""
read -n1 -rep "${CAT} Would you like to reboot now? (y/n): " REBOOT
if [[ $REBOOT =~ ^[Yy]$ ]]; then
    echo "${NOTE} Rebooting..."
    sleep 2
    systemctl reboot
fi
