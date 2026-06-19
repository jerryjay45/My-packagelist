#!/bin/bash

set -uo pipefail

PACMAN_FAILED="pacman-failed.txt"
AUR_FAILED="aur-failed.txt"

echo "Updating system..."
sudo pacman -Syu --noconfirm

echo "Installing prerequisites..."
sudo pacman -S --needed --noconfirm git curl base-devel

####################################
# Install CachyOS repo
####################################
if ! pacman -Sl cachyos >/dev/null 2>&1; then
    echo "Installing CachyOS repositories..."

    curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz | tar -xJ

    cd cachyos-repo || exit 1
    chmod +x cachyos-repo.sh
    sudo ./cachyos-repo.sh
    cd .. || exit 1
fi

####################################
# Install Chaotic-AUR repo
####################################
if ! pacman -Sl chaotic-aur >/dev/null 2>&1; then
    echo "Installing Chaotic-AUR..."

    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB

    sudo pacman -U --noconfirm \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst

    if ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf; then
        sudo tee -a /etc/pacman.conf >/dev/null <<EOF

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
    fi
fi

echo "Refreshing package databases..."
sudo pacman -Syy

####################################
# Install yay from Chaotic-AUR
####################################
echo "Installing yay..."
sudo pacman -S --needed --noconfirm yay

rm -f "$PACMAN_FAILED" "$AUR_FAILED"

####################################
# Install pacman packages
####################################
echo "Installing pacman packages..."

if sudo pacman -S --needed --noconfirm $(< package-pacman.txt); then
    echo "Pacman packages installed successfully."
else
    echo "Bulk pacman install failed."
    echo "Retrying package-by-package..."

    while read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue

        if ! pacman -Qi "$pkg" &>/dev/null; then
            if sudo pacman -S --needed --noconfirm "$pkg"; then
                echo "Installed $pkg"
            else
                echo "$pkg" | tee -a "$PACMAN_FAILED"
            fi
        fi
    done < package-pacman.txt
fi

####################################
# Install AUR packages
####################################
echo "Installing AUR packages..."

if yay -S --needed --noconfirm $(< aur-packages.txt); then
    echo "AUR packages installed successfully."
else
    echo "Bulk AUR install failed."
    echo "Retrying package-by-package..."

    while read -r pkg; do
        [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue

        if ! pacman -Qi "$pkg" &>/dev/null; then
            if yay -S --needed --noconfirm "$pkg"; then
                echo "Installed $pkg"
            else
                echo "$pkg" | tee -a "$AUR_FAILED"
            fi
        fi
    done < aur-packages.txt
fi

####################################
# Summary
####################################
echo
echo "Installation complete."

if [[ -f "$PACMAN_FAILED" ]]; then
    echo "Some pacman packages failed to install:"
    cat "$PACMAN_FAILED"
fi

if [[ -f "$AUR_FAILED" ]]; then
    echo "Some AUR packages failed to install:"
    cat "$AUR_FAILED"
fi

if [[ ! -f "$PACMAN_FAILED" && ! -f "$AUR_FAILED" ]]; then
    echo "All packages installed successfully."
fi
