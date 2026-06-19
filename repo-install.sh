#!/bin/bash

set -e

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
    cd cachyos-repo
    chmod +x cachyos-repo.sh
    sudo ./cachyos-repo.sh
    cd ..
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

    if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
        echo "" | sudo tee -a /etc/pacman.conf
        echo "[chaotic-aur]" | sudo tee -a /etc/pacman.conf
        echo "Include = /etc/pacman.d/chaotic-mirrorlist" | sudo tee -a /etc/pacman.conf
    fi
fi

sudo pacman -Syy

echo "Installing yay..."
sudo pacman -S --needed --noconfirm yay

rm -f "$PACMAN_FAILED"
rm -f "$AUR_FAILED"

echo "Installing pacman packages..."

while read -r pkg; do
    [[ -z "$pkg" ]] && continue

    if sudo pacman -S --needed --noconfirm "$pkg"; then
        echo "Installed $pkg"
    else
        echo "$pkg" >> "$PACMAN_FAILED"
    fi
done < package-pacman.txt

echo "Installing AUR packages..."

while read -r pkg; do
    [[ -z "$pkg" ]] && continue

    if yay -S --needed --noconfirm "$pkg"; then
        echo "Installed $pkg"
    else
        echo "$pkg" >> "$AUR_FAILED"
    fi
done < aur-packages.txt

echo "Done."

[[ -f "$PACMAN_FAILED" ]] && echo "Failed pacman packages logged to $PACMAN_FAILED"
[[ -f "$AUR_FAILED" ]] && echo "Failed AUR packages logged to $AUR_FAILED"
