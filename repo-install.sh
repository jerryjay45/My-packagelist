#!/bin/bash
set -e

OFFICIAL_PACKAGES=(
    firefox
    git
)

CACHYOS_PACKAGES=(
    linux-cachyos
)

CHAOTIC_PACKAGES=(
    proton-ge-custom-bin
    yay
)

AUR_PACKAGES=(
    visual-studio-code-bin
)

echo "Updating system..."
sudo pacman -Syu --noconfirm

echo "Installing prerequisites..."
sudo pacman -S --needed --noconfirm curl git base-devel

# Install CachyOS repo
if ! pacman -Sl cachyos >/dev/null 2>&1; then
    curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz | tar -xJ
    cd cachyos-repo
    chmod +x cachyos-repo.sh
    sudo ./cachyos-repo.sh
    cd ..
fi

# Install Chaotic-AUR repo
if ! pacman -Sl chaotic-aur >/dev/null 2>&1; then
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB

    sudo pacman -U --noconfirm \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst \
        https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst

    echo '
[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist' | sudo tee -a /etc/pacman.conf
fi

sudo pacman -Sy

# Install packages from repos
sudo pacman -S --needed --noconfirm \
    "${OFFICIAL_PACKAGES[@]}" \
    "${CACHYOS_PACKAGES[@]}" \
    "${CHAOTIC_PACKAGES[@]}"

# Install AUR packages
yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"
