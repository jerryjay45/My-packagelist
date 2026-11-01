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

# A failure on the left side of a pipe (e.g. pacman | tee) must count as a failure
set -o pipefail

clear

# --- Colors (tput style, like JaKooLit) ---
OK="$(tput setaf 2)[OK]$(tput sgr0)"
ERROR="$(tput setaf 1)[ERROR]$(tput sgr0)"
NOTE="$(tput setaf 3)[NOTE]$(tput sgr0)"
WARN="$(tput setaf 166)[WARN]$(tput sgr0)"
CAT="$(tput setaf 6)[ACTION]$(tput sgr0)"
INFO="$(tput setaf 4)[INFO]$(tput sgr0)"
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

# --- Settings ---
PACMAN_CONF="/etc/pacman.conf"
LOG="install-$(date +%Y%m%d-%H%M%S).log"
FAILED_LOG="failed-packages.txt"
echo "Install log: $LOG"
echo ""

# --- GitHub URLs ---
GITHUB_RAW="https://raw.githubusercontent.com/jerryjay45/My-packagelist/main"
PACMAN_LIST_URL="$GITHUB_RAW/package-pacman.txt"
AUR_LIST_URL="$GITHUB_RAW/aur-packages.txt"

# Answers to the optional prompts (default: no)
setup_cachyos="N"
setup_chaotic="N"
install_yay="N"
setup_resolve="N"

# Install counters (used by install_group)
INSTALLED=0
FAILED=0
CURRENT=0
TOTAL_COUNT=0

# ============================================================
# Helper functions
# ============================================================
# BEGIN FUNCTIONS

colorize_prompt() {
    local color="$1"
    local message="$2"
    echo -n "${color}${message}$(tput sgr0)"
}

# ask_yes_no "question" variable_name  ->  sets variable to Y or N
ask_yes_no() {
    local prompt="$1" var="$2" choice
    while true; do
        read -rp "$(colorize_prompt "$CAT" "$prompt (y/n): ")" choice
        case "$choice" in
            [Yy]* ) printf -v "$var" '%s' "Y"; return 0 ;;
            [Nn]* ) printf -v "$var" '%s' "N"; return 1 ;;
            * ) echo "Please answer with y or n." ;;
        esac
    done
}

# Run a command, show its output AND append it to the log,
# but return the command's real exit status (not tee's).
log_run() {
    "$@" 2>&1 | tee -a "$LOG"
    return "${PIPESTATUS[0]}"
}

# Strip CRs, comments and blank lines; remove duplicates but keep order.
clean_list() {
    sed -e 's/\r$//' -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | awk 'NF && !seen[$0]++'
}

# Make sure [multilib] is enabled (needed for lib32-*, steam, wine).
enable_multilib() {
    if grep -q '^\[multilib\]' "$PACMAN_CONF"; then
        echo "${OK} multilib already enabled." | tee -a "$LOG"
    elif grep -q '^#\[multilib\]' "$PACMAN_CONF"; then
        sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' "$PACMAN_CONF"
        echo "${OK} multilib enabled." | tee -a "$LOG"
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a "$PACMAN_CONF" > /dev/null
        echo "${OK} multilib section added." | tee -a "$LOG"
    fi
}

# Prints the highest x86-64 level the CPU supports: v4, v3 or none.
detect_cpu_level() {
    local out ld
    for ld in /lib/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2; do
        [[ -x "$ld" ]] && break
    done
    out=$("$ld" --help 2>/dev/null | grep -E 'x86-64-v[0-9]+ \(supported')
    if grep -q 'x86-64-v4' <<< "$out"; then
        echo "v4"
    elif grep -q 'x86-64-v3' <<< "$out"; then
        echo "v3"
    else
        echo "none"
    fi
}

# Prints the pacman.conf block for CachyOS. $1 = v4 | v3 | none
build_cachyos_block() {
    local level="$1" repo
    if [[ "$level" != "none" ]]; then
        for repo in "cachyos-${level}" "cachyos-core-${level}" "cachyos-extra-${level}"; do
            printf '[%s]\nInclude = /etc/pacman.d/cachyos-%s-mirrorlist\n\n' "$repo" "$level"
        done
    fi
    printf '[cachyos]\nInclude = /etc/pacman.d/cachyos-mirrorlist\n'
}

# Insert the contents of file $1 above the first [core] line of pacman.conf.
insert_repos_before_core() {
    local block_file="$1" tmp
    if ! grep -q '^\[core\]' "$PACMAN_CONF"; then
        return 1
    fi
    tmp=$(mktemp)
    awk -v blockfile="$block_file" '
        /^\[core\]/ && !done {
            while ((getline line < blockfile) > 0) print line
            print ""
            done = 1
        }
        { print }
    ' "$PACMAN_CONF" > "$tmp"
    sudo install -m 644 "$tmp" "$PACMAN_CONF"
    rm -f "$tmp"
}

# run_installer <pacman|yay> <visible|quiet> packages...
run_installer() {
    local tool="$1" mode="$2"
    shift 2
    if [[ "$mode" == "visible" ]]; then
        if [[ "$tool" == "pacman" ]]; then
            log_run sudo pacman -S --needed --noconfirm "$@"
        else
            log_run yay -S --needed --noconfirm "$@"
        fi
    else
        # The log is deliberately written as the normal user, not root
        if [[ "$tool" == "pacman" ]]; then
            # shellcheck disable=SC2024
            sudo pacman -S --needed --noconfirm "$@" >> "$LOG" 2>&1
        else
            yay -S --needed --noconfirm "$@" >> "$LOG" 2>&1
        fi
    fi
}

# install_group <label> <pacman|yay> packages...
# Tries one big transaction first; if that fails, retries package by package
# so a single bad package doesn't take everything else down with it.
install_group() {
    local label="$1" tool="$2" pkg
    shift 2
    local pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && return 0

    echo "" | tee -a "$LOG"
    echo "${INFO} Installing ${#pkgs[@]} ${label} packages in one transaction..." | tee -a "$LOG"
    if run_installer "$tool" visible "${pkgs[@]}"; then
        INSTALLED=$((INSTALLED + ${#pkgs[@]}))
        CURRENT=$((CURRENT + ${#pkgs[@]}))
        echo "${OK} ${label} packages installed." | tee -a "$LOG"
        return 0
    fi

    echo "${WARN} Bulk ${label} install failed — retrying one package at a time..." | tee -a "$LOG"
    for pkg in "${pkgs[@]}"; do
        CURRENT=$((CURRENT + 1))
        echo -n "${INFO} [$CURRENT/$TOTAL_COUNT] Installing ${CYAN}${pkg}${RESET}... "
        if run_installer "$tool" quiet "$pkg"; then
            echo "${OK}"
            INSTALLED=$((INSTALLED + 1))
        else
            echo "${ERROR}"
            echo "$pkg" >> "$FAILED_LOG"
            FAILED=$((FAILED + 1))
        fi
    done
}

# Split $ALL_PACKAGES into:
#   REPO_PKGS    - available in an enabled sync repo (incl. Chaotic/CachyOS, prebuilt)
#   YAY_PKGS     - everything else, built from the AUR
#   SKIPPED_PKGS - CachyOS kernels that are not in an enabled repo. These are
#                  never sent to the AUR: a kernel build from source takes hours.
split_packages() {
    local name pkg
    local -A in_repo=()
    while IFS= read -r name; do
        in_repo["$name"]=1
    done < <(pacman -Slq)

    REPO_PKGS=()
    YAY_PKGS=()
    SKIPPED_PKGS=()
    while IFS= read -r pkg; do
        if [[ -n "${in_repo[$pkg]:-}" ]]; then
            REPO_PKGS+=("$pkg")
        elif [[ "$pkg" == linux-cachyos* ]]; then
            SKIPPED_PKGS+=("$pkg")
        else
            YAY_PKGS+=("$pkg")
        fi
    done <<< "$ALL_PACKAGES"
}

# DKMS modules need headers for every installed kernel.
install_kernel_headers() {
    local f pkgbase headers
    local -a to_install=()
    for f in /usr/lib/modules/*/pkgbase; do
        [[ -r "$f" ]] || continue
        pkgbase=$(<"$f")
        headers="${pkgbase}-headers"
        if pacman -Si "$headers" &>/dev/null; then
            to_install+=("$headers")
        else
            echo "${WARN} No headers package found for kernel '$pkgbase' (looked for $headers)." | tee -a "$LOG"
        fi
    done
    if [[ ${#to_install[@]} -eq 0 ]]; then
        echo "${WARN} No kernel headers could be determined — DKMS packages may fail to build." | tee -a "$LOG"
        return 1
    fi
    log_run sudo pacman -S --needed --noconfirm "${to_install[@]}"
}

# END FUNCTIONS

# --- Welcome ---
echo "$(tput setaf 6)Welcome to Jerry's Arch Linux POS Installer!$(tput sgr0)"
echo ""
echo "${NOTE} This script will:"
echo "  1. Enable the multilib repository"
echo "  2. (Optional) Set up the CachyOS and/or Chaotic-AUR repositories"
echo "  3. Update your system"
echo "  4. (Optional) Install yay"
echo "  5. Install every package from your GitHub package lists"
echo "  6. (Optional) Set up DaVinci Resolve with Rusticl OpenCL for AMD Polaris GPUs"
echo ""
read -rp "$(colorize_prompt "$CAT" "Would you like to proceed? (y/n): ")" proceed
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
ask_yes_no "Set up DaVinci Resolve (AMD Rusticl OpenCL fix for Polaris GPUs)?" setup_resolve
printf "\n"

# --- Ask package list source ---
echo "${CAT} Where should the package lists be loaded from?"
echo "  1) GitHub (fetch latest from repo)"
echo "  2) Local  (use lists in this cloned directory)"
while true; do
    read -rp "$(colorize_prompt "$CAT" "Enter 1 or 2: ")" list_source
    case "$list_source" in
        1) USE_LOCAL="N"; break ;;
        2) USE_LOCAL="Y"; break ;;
        *) echo "Please enter 1 or 2." ;;
    esac
done
printf "\n"

# If local, verify the files exist next to the script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$USE_LOCAL" == "Y" ]]; then
    if [[ ! -f "$SCRIPT_DIR/package-pacman.txt" || ! -f "$SCRIPT_DIR/aur-packages.txt" ]]; then
        echo "${ERROR} Local package lists not found in $SCRIPT_DIR" | tee -a "$LOG"
        echo "${NOTE} Make sure package-pacman.txt and aur-packages.txt are in the same folder as this script." | tee -a "$LOG"
        exit 1
    fi
    echo "${OK} Using local package lists from: $SCRIPT_DIR" | tee -a "$LOG"
fi

# --- Authenticate once and keep sudo alive (long installs outlast the sudo timeout) ---
echo "${INFO} Requesting sudo access..."
if ! sudo -v; then
    echo "${ERROR} sudo authentication failed."
    exit 1
fi
(
    while true; do
        sudo -n true 2>/dev/null
        sleep 50
        kill -0 "$$" 2>/dev/null || exit
    done
) &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT

# ============================================================
# STEP 1 - Enable multilib
# ============================================================
echo ""
echo "${INFO} Checking multilib repository..." | tee -a "$LOG"
enable_multilib
sleep 1

# ============================================================
# STEP 2a - CachyOS Repositories
# ============================================================
if [[ "$setup_cachyos" == "Y" ]]; then
    echo ""
    echo "${INFO} Setting up CachyOS repositories..." | tee -a "$LOG"
    if grep -q '^\[cachyos' "$PACMAN_CONF" 2>/dev/null; then
        echo "${WARN} CachyOS repositories already present — skipping." | tee -a "$LOG"
    else
        CPU_LEVEL=$(detect_cpu_level)
        echo "${INFO} Highest supported CPU level: ${CPU_LEVEL}" | tee -a "$LOG"
        if [[ "$CPU_LEVEL" == "none" ]]; then
            echo "${NOTE} CPU lacks x86-64-v3 — only the base [cachyos] repo will be added." | tee -a "$LOG"
        fi

        # Receive and sign the CachyOS key
        log_run sudo pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
        log_run sudo pacman-key --lsign-key F3B607488DB35A47

        # Resolve the current package filenames from the mirror (one request)
        CACHYOS_MIRROR="https://mirror.cachyos.org/repo/x86_64/cachyos"
        CACHYOS_INDEX=$(curl -fsSL "$CACHYOS_MIRROR/")
        KEYRING=$(grep -oP 'cachyos-keyring-[^"]+\.pkg\.tar\.zst' <<< "$CACHYOS_INDEX" | head -1)
        MIRRORLIST=$(grep -oP 'cachyos-mirrorlist-[^"]+\.pkg\.tar\.zst' <<< "$CACHYOS_INDEX" | head -1)
        CACHYOS_PKGS=("$KEYRING" "$MIRRORLIST")
        if [[ "$CPU_LEVEL" != "none" ]]; then
            LEVEL_MIRRORLIST=$(grep -oP "cachyos-${CPU_LEVEL}-mirrorlist-[^\"]+\.pkg\.tar\.zst" <<< "$CACHYOS_INDEX" | head -1)
            CACHYOS_PKGS+=("$LEVEL_MIRRORLIST")
        fi

        resolved=1
        for p in "${CACHYOS_PKGS[@]}"; do
            [[ -z "$p" ]] && resolved=0
        done

        if [[ $resolved -eq 0 ]]; then
            echo "${ERROR} Could not resolve CachyOS package filenames from mirror. Skipping." | tee -a "$LOG"
        else
            echo "${INFO} Found: ${CACHYOS_PKGS[*]}" | tee -a "$LOG"
            CACHYOS_URLS=()
            for p in "${CACHYOS_PKGS[@]}"; do
                CACHYOS_URLS+=("$CACHYOS_MIRROR/$p")
            done

            if log_run sudo pacman -U --noconfirm "${CACHYOS_URLS[@]}"; then
                BACKUP="${PACMAN_CONF}.bak-$(date +%Y%m%d-%H%M%S)"
                sudo cp "$PACMAN_CONF" "$BACKUP"
                BLOCK_FILE=$(mktemp)
                build_cachyos_block "$CPU_LEVEL" > "$BLOCK_FILE"
                if insert_repos_before_core "$BLOCK_FILE"; then
                    echo "${OK} CachyOS repositories added above [core] (backup: $BACKUP)." | tee -a "$LOG"
                else
                    echo "${ERROR} No [core] section found in $PACMAN_CONF — CachyOS repos NOT added." | tee -a "$LOG"
                fi
                rm -f "$BLOCK_FILE"
            else
                echo "${ERROR} CachyOS package install failed. Skipping pacman.conf changes." | tee -a "$LOG"
            fi
        fi
    fi
fi
sleep 1

# ============================================================
# STEP 2b - Chaotic-AUR Repository
# ============================================================
if [[ "$setup_chaotic" == "Y" ]]; then
    echo ""
    echo "${INFO} Setting up Chaotic-AUR repository..." | tee -a "$LOG"
    if grep -q '^\[chaotic-aur\]' "$PACMAN_CONF" 2>/dev/null; then
        echo "${WARN} Chaotic-AUR already present — skipping." | tee -a "$LOG"
    else
        log_run sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
        log_run sudo pacman-key --lsign-key 3056513887B78AEB
        if log_run sudo pacman -U --noconfirm \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
            'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'; then

            cat <<'EOF' | sudo tee -a "$PACMAN_CONF" > /dev/null

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
            echo "${OK} Chaotic-AUR repository added." | tee -a "$LOG"
        else
            echo "${ERROR} Failed to install Chaotic-AUR keyring/mirrorlist. Skipping to avoid breaking pacman.conf." | tee -a "$LOG"
        fi
    fi
fi
sleep 1

# ============================================================
# STEP 3 - Sanity check pacman.conf, then full system update
# ============================================================
echo ""
echo "${INFO} Verifying pacman.conf is valid..." | tee -a "$LOG"
if ! sudo pacman -Sy --noconfirm > /dev/null 2>&1; then
    echo "${ERROR} pacman.conf appears broken — likely a missing mirrorlist file." | tee -a "$LOG"
    echo "${NOTE} Check $PACMAN_CONF and remove any repo entries whose Include files don't exist." | tee -a "$LOG"
    exit 1
fi
echo "${OK} pacman.conf is valid." | tee -a "$LOG"
sleep 1

echo ""
echo "${INFO} Updating system..." | tee -a "$LOG"
if ! log_run sudo pacman -Syu --noconfirm; then
    echo "${ERROR} System update failed — stopping so packages aren't installed on a half-updated system." | tee -a "$LOG"
    exit 1
fi
echo "${OK} System updated." | tee -a "$LOG"
sleep 1

# ============================================================
# STEP 4 - Install yay (after the update, so there is no partial upgrade)
# ============================================================
if [[ "$install_yay" == "Y" ]]; then
    if ! command -v yay &>/dev/null; then
        echo ""
        echo "${INFO} Installing yay AUR helper..." | tee -a "$LOG"
        log_run sudo pacman -S --needed --noconfirm git base-devel
        if pacman -Si yay &>/dev/null; then
            # Available prebuilt from Chaotic-AUR / CachyOS
            log_run sudo pacman -S --needed --noconfirm yay
        else
            TMPDIR=$(mktemp -d)
            git clone https://aur.archlinux.org/yay.git "$TMPDIR/yay" 2>&1 | tee -a "$LOG"
            (cd "$TMPDIR/yay" && makepkg -si --noconfirm 2>&1 | tee -a "$LOG")
            rm -rf "$TMPDIR"
        fi
        if command -v yay &>/dev/null; then
            echo "${OK} yay installed." | tee -a "$LOG"
        else
            echo "${ERROR} yay installation failed." | tee -a "$LOG"
        fi
    else
        echo "${OK} yay is already installed: $(yay --version | head -1)" | tee -a "$LOG"
    fi
fi

if ! command -v yay &>/dev/null; then
    echo "${ERROR} yay is required to install the package lists but was not found." | tee -a "$LOG"
    echo "${NOTE} Re-run the script and answer 'y' to the yay prompt." | tee -a "$LOG"
    exit 1
fi
sleep 1

# ============================================================
# STEP 5 - Load package lists (GitHub or local)
# ============================================================
echo ""

if [[ "$USE_LOCAL" == "Y" ]]; then
    echo "${INFO} Loading package lists from local directory..." | tee -a "$LOG"
    PACMAN_PACKAGES=$(clean_list < "$SCRIPT_DIR/package-pacman.txt")
    AUR_PACKAGES=$(clean_list < "$SCRIPT_DIR/aur-packages.txt")
else
    echo "${INFO} Fetching package lists from GitHub..." | tee -a "$LOG"
    PACMAN_PACKAGES=$(curl -fsSL "$PACMAN_LIST_URL" | clean_list)
    AUR_PACKAGES=$(curl -fsSL "$AUR_LIST_URL" | clean_list)
fi

if [[ -z "$PACMAN_PACKAGES" ]]; then
    echo "${ERROR} Failed to load pacman package list." | tee -a "$LOG"
    exit 1
fi

if [[ -z "$AUR_PACKAGES" ]]; then
    echo "${ERROR} Failed to load AUR package list." | tee -a "$LOG"
    exit 1
fi

# Combine both lists (duplicates across the two files are removed)
ALL_PACKAGES=$(printf "%s\n%s\n" "$PACMAN_PACKAGES" "$AUR_PACKAGES" | clean_list)
TOTAL_COUNT=$(wc -l <<< "$ALL_PACKAGES")
echo "${OK} Loaded $TOTAL_COUNT unique packages (pacman + AUR lists)." | tee -a "$LOG"

: > "$FAILED_LOG"

split_packages
echo "${INFO} ${#REPO_PKGS[@]} from sync repos, ${#YAY_PKGS[@]} via yay (AUR)." | tee -a "$LOG"
if [[ ${#SKIPPED_PKGS[@]} -gt 0 ]]; then
    echo "${WARN} Skipping ${#SKIPPED_PKGS[@]} package(s) that only exist in the CachyOS repos, which are not enabled: ${SKIPPED_PKGS[*]}" | tee -a "$LOG"
    echo "${NOTE} Re-run and answer 'y' to the CachyOS prompt (or enable the repos) to install them." | tee -a "$LOG"
    printf '%s\n' "${SKIPPED_PKGS[@]}" >> "$FAILED_LOG"
    FAILED=$((FAILED + ${#SKIPPED_PKGS[@]}))
fi
sleep 1

# ============================================================
# STEP 6 - Install packages
# ============================================================
if grep -qE -- '-dkms$' <<< "$ALL_PACKAGES"; then
    echo ""
    echo "${INFO} DKMS packages in list — installing kernel headers first..." | tee -a "$LOG"
    install_kernel_headers
fi

echo ""
echo "${INFO} Installing packages ($TOTAL_COUNT total)..." | tee -a "$LOG"
install_group "repo" pacman "${REPO_PKGS[@]}"
install_group "AUR"  yay    "${YAY_PKGS[@]}"

echo ""
echo "${OK} ${GREEN}$INSTALLED installed${RESET} | ${RED}$FAILED failed${RESET}" | tee -a "$LOG"
[[ $FAILED -gt 0 ]] && echo "${WARN} Failed packages logged to: $FAILED_LOG" | tee -a "$LOG"

# ============================================================
# STEP 7 - DaVinci Resolve (Rusticl OpenCL fix for AMD Polaris GPUs)
# ============================================================
if [[ "$setup_resolve" == "Y" ]]; then
    echo ""
    echo "${INFO} Setting up DaVinci Resolve with Rusticl OpenCL support..." | tee -a "$LOG"

    RUSTICL_DRIVER="radeonsi"   # change to "iris" for Intel, "nouveau" for older NVIDIA open-source

    # --- Rusticl OpenCL stack (+ clinfo for the verification at the end) ---
    echo "${INFO} Installing opencl-mesa, ocl-icd and clinfo..." | tee -a "$LOG"
    log_run sudo pacman -S --needed --noconfirm opencl-mesa ocl-icd clinfo

    # --- Remove conflicting ROCm OpenCL runtime, if present ---
    if pacman -Qi rocm-opencl-runtime &>/dev/null; then
        echo "${WARN} rocm-opencl-runtime detected — removing (conflicts with Rusticl on pre-Vega GPUs)." | tee -a "$LOG"
        log_run sudo pacman -R --noconfirm rocm-opencl-runtime
    else
        echo "${OK} rocm-opencl-runtime not installed, nothing to remove." | tee -a "$LOG"
    fi

    # --- Add user to render/video groups ---
    echo "${INFO} Ensuring $USER is in render and video groups..." | tee -a "$LOG"
    log_run sudo usermod -aG render,video "$USER"

    # --- Install davinci-resolve + checker from AUR ---
    if ! pacman -Qi davinci-resolve &>/dev/null; then
        echo "${INFO} Installing davinci-resolve from AUR..." | tee -a "$LOG"
        log_run yay -S --needed --noconfirm davinci-resolve
    else
        echo "${OK} davinci-resolve already installed." | tee -a "$LOG"
    fi

    if ! pacman -Qi davinci-resolve-checker &>/dev/null; then
        echo "${INFO} Installing davinci-resolve-checker from AUR..." | tee -a "$LOG"
        log_run yay -S --needed --noconfirm davinci-resolve-checker
    else
        echo "${OK} davinci-resolve-checker already installed." | tee -a "$LOG"
    fi

    # --- Patch the .desktop launcher to always set RUSTICL_ENABLE ---
    SYSTEM_DESKTOP=$(find /usr/share/applications /opt -maxdepth 4 -iname "*resolve*.desktop" 2>/dev/null | head -n1 || true)
    USER_APPS_DIR="$HOME/.local/share/applications"
    USER_DESKTOP="$USER_APPS_DIR/davinci-resolve.desktop"

    if [[ -n "$SYSTEM_DESKTOP" ]]; then
        mkdir -p "$USER_APPS_DIR"
        cp "$SYSTEM_DESKTOP" "$USER_DESKTOP"
        if ! grep -q "RUSTICL_ENABLE=" "$USER_DESKTOP"; then
            sed -i -E "s|^Exec=(.*)|Exec=env RUSTICL_ENABLE=${RUSTICL_DRIVER} \1|" "$USER_DESKTOP"
            echo "${OK} Patched launcher to export RUSTICL_ENABLE=${RUSTICL_DRIVER}: $USER_DESKTOP" | tee -a "$LOG"
        else
            echo "${OK} Launcher already has RUSTICL_ENABLE set." | tee -a "$LOG"
        fi
    else
        echo "${WARN} Could not auto-locate a DaVinci Resolve .desktop file." | tee -a "$LOG"
        echo "${NOTE} Launch manually with: RUSTICL_ENABLE=${RUSTICL_DRIVER} davinci-resolve" | tee -a "$LOG"
    fi

    # --- Verify OpenCL sees the GPU ---
    if command -v clinfo &>/dev/null; then
        echo "${INFO} Verifying Rusticl device detection..." | tee -a "$LOG"
        RUSTICL_ENABLE="$RUSTICL_DRIVER" clinfo 2>&1 | grep -E "Platform Name|Number of devices|Device Name" | tee -a "$LOG"
    else
        echo "${NOTE} Install clinfo (sudo pacman -S clinfo) to verify GPU detection manually." | tee -a "$LOG"
    fi

    echo "${OK} DaVinci Resolve setup complete. Log out/in for group changes to take effect." | tee -a "$LOG"
fi
sleep 1

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
