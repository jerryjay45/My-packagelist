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

       __                    
      / /__  ____________  __
 __  / / _ \/ ___/ ___/ / / /
/ /_/ /  __/ /  / /  / /_/ / 
\____/\___/_/  /_/   \__, /  
                    /____/   

   ______                _                ____  _      
  / ____/___ _____ ___  (_)___  ____ _   / __ \(_)___ _
 / / __/ __ `/ __ `__ \/ / __ \/ __ `/  / /_/ / / __ `/
/ /_/ / /_/ / / / / / / / / / / /_/ /  / _, _/ / /_/ / 
\____/\__,_/_/ /_/ /_/_/_/ /_/\__, /  /_/ |_/_/\__, /  
                             /____/           /____/   

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

FAILED_LOG="failed-packages.txt"

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
echo "  4. Install all packages from your GitHub package lists via yay"
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
# STEP 1 - Install yay (needs git/base-devel first, no repo setup needed)
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
        echo "${INFO} Downloading CachyOS repo-add script..." | tee -a "$LOG"
        curl -o /tmp/cachyos-repo-add.sh https://mirror.cachyos.org/cachyos-repo-add.sh 2>&1 | tee -a "$LOG"
        if [[ ! -f /tmp/cachyos-repo-add.sh ]]; then
            echo "${ERROR} Failed to download CachyOS repo-add script. Skipping." | tee -a "$LOG"
        else
            chmod +x /tmp/cachyos-repo-add.sh
            sudo /tmp/cachyos-repo-add.sh 2>&1 | tee -a "$LOG"
            rm -f /tmp/cachyos-repo-add.sh
            echo "${OK} CachyOS repositories added." | tee -a "$LOG"
        fi
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
        if sudo pacman -U --noconfirm \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' 2>&1 | tee -a "$LOG"; then

            cat <<'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
            sudo pacman -Sy 2>&1 | tee -a "$LOG"
            echo "${OK} Chaotic-AUR repository added." | tee -a "$LOG"
        else
            echo "${ERROR} Failed to install Chaotic-AUR keyring/mirrorlist. Skipping to avoid breaking pacman.conf." | tee -a "$LOG"
        fi
    fi
fi
sleep 1

# ============================================================
# STEP 5 - Sanity Check pacman.conf
# ============================================================
echo ""
echo "${INFO} Verifying pacman.conf is valid..." | tee -a "$LOG"
if ! sudo pacman -Sy --noconfirm > /dev/null 2>&1; then
    echo "${ERROR} pacman.conf appears broken — likely a missing mirrorlist file." | tee -a "$LOG"
    echo "${NOTE} Check /etc/pacman.conf and remove any repo entries whose Include files don't exist." | tee -a "$LOG"
    exit 1
fi
echo "${OK} pacman.conf is valid." | tee -a "$LOG"
sleep 1

# ============================================================
# STEP 6 - System Update (after repos are confirmed working)
# ============================================================
echo ""
echo "${INFO} Updating system..." | tee -a "$LOG"
sudo pacman -Syu --noconfirm 2>&1 | tee -a "$LOG"
echo "${OK} System updated." | tee -a "$LOG"
sleep 1

# ============================================================
# STEP 7 - Fetch Package Lists
# ============================================================
echo ""
echo "${INFO} Fetching package lists from GitHub..." | tee -a "$LOG"

PACMAN_PACKAGES=$(curl -fsSL "$PACMAN_LIST_URL" | grep -v '^\s*#' | grep -v '^\s*$')
if [[ -z "$PACMAN_PACKAGES" ]]; then
    echo "${ERROR} Failed to fetch pacman package list. Check your internet or repo URL." | tee -a "$LOG"
    exit 1
fi

AUR_PACKAGES=$(curl -fsSL "$AUR_LIST_URL" | grep -v '^\s*#' | grep -v '^\s*$')
if [[ -z "$AUR_PACKAGES" ]]; then
    echo "${ERROR} Failed to fetch AUR package list. Check your internet or repo URL." | tee -a "$LOG"
    exit 1
fi

# Combine both lists
ALL_PACKAGES=$(printf "%s\n%s" "$PACMAN_PACKAGES" "$AUR_PACKAGES" | grep -v '^\s*$')
TOTAL_COUNT=$(echo "$ALL_PACKAGES" | wc -l)
echo "${OK} Fetched $TOTAL_COUNT packages total (pacman + AUR)." | tee -a "$LOG"

> "$FAILED_LOG"
sleep 1

# ============================================================
# STEP 8 - Install All Packages via yay
# ============================================================
echo ""
echo "${INFO} Installing all packages via yay ($TOTAL_COUNT total)..." | tee -a "$LOG"

INSTALLED=0
FAILED=0
CURRENT=0

while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    CURRENT=$((CURRENT + 1))
    echo -n "${INFO} [$CURRENT/$TOTAL_COUNT] Installing ${CYAN}$pkg${RESET}... "
    if yay -S --needed --noconfirm "$pkg" >> "$LOG" 2>&1; then
        echo "${OK}"
        INSTALLED=$((INSTALLED + 1))
    else
        echo "${ERROR}"
        echo "$pkg" >> "$FAILED_LOG"
        FAILED=$((FAILED + 1))
    fi
done <<< "$ALL_PACKAGES"

echo ""
echo "${OK} ${GREEN}$INSTALLED installed${RESET} | ${RED}$FAILED failed${RESET}" | tee -a "$LOG"
[[ $FAILED -gt 0 ]] && echo "${WARN} Failed packages logged to: $FAILED_LOG" | tee -a "$LOG"

# ============================================================
# DONE
# ============================================================
clear
printf "\n${OK} ${GREEN}Yey! Installation Completed.${RESET}\n\n"

echo "  Total  : ${GREEN}$INSTALLED installed${RESET}  |  ${RED}$FAILED failed${RESET}"
echo ""

if [[ -s "$FAILED_LOG" ]]; then
    echo "${WARN} Some packages failed to install. Review the log:"
    echo "  → $FAILED_LOG"
    echo ""
fi

echo "${NOTE} Full install log: ${YELLOW}$LOG${RESET}"
[[ -s "$FAILED_LOG" ]] && echo "${NOTE} Failed packages:  ${YELLOW}$FAILED_LOG${RESET}"
echo ""
read -n1 -rep "${CAT} Would you like to reboot now? (y/n): " REBOOT
if [[ $REBOOT =~ ^[Yy]$ ]]; then
    echo "${NOTE} Rebooting..."
    sleep 2
    systemctl reboot
fi
