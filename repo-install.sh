#!/bin/bash
set -e

REPO_URL="https://github.com/jerryjay45/My-packagelist.git"
WORKDIR="/tmp/My-packagelist"

sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm git curl base-devel

# Clone package lists
rm -rf "$WORKDIR"
git clone "$REPO_URL" "$WORKDIR"

####################################
# Install CachyOS repo
####################################
curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz | tar -xJ
cd cachyos-repo
chmod +x cachyos-repo.sh
sudo ./cachyos-repo.sh
cd ..

####################################
# Install Chaotic-AUR repo
####################################
sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
sudo pacman-key --lsign-key 3056513887B78AEB

sudo pacman -U --noconfirm \
https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst \
https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst

if ! grep -q "\[chaotic-aur\]" /etc/pacman.conf; then
sudo tee -a /etc/pacman.conf <<EOF

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF
fi

sudo pacman -Syy

####################################
# Install yay from Chaotic-AUR
####################################
sudo pacman -S --needed --noconfirm yay

####################################
# Install packages
####################################
cd "$WORKDIR"

sudo pacman -S --needed $(< package-pacman.txt)
yay -S --needed $(< aur-packages.txt)

echo "Done."
