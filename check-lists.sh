#!/bin/bash

# ============================================================
# check-lists.sh - find stale or renamed packages in the lists
# ============================================================
# Reads package-pacman.txt and aur-packages.txt from this directory and
# reports every entry that can't be found in the enabled sync repos or the AUR.
# Run it on an Arch install that has the same repos enabled as the target
# (multilib, and CachyOS / Chaotic-AUR if the lists use them).
#
# Usage: ./check-lists.sh
# Exit status: 0 = everything found, 1 = at least one package missing.

if [[ $EUID -eq 0 ]]; then
    echo "Run this as a normal user, not root." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTS=("$SCRIPT_DIR/package-pacman.txt" "$SCRIPT_DIR/aur-packages.txt")

# BEGIN FUNCTIONS
clean_list() {
    sed -e 's/\r$//' -e 's/[[:space:]]*#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | awk 'NF && !seen[$0]++'
}
# END FUNCTIONS

for f in "${LISTS[@]}"; do
    if [[ ! -f "$f" ]]; then
        echo "Missing list file: $f" >&2
        exit 1
    fi
done

if ! command -v yay &>/dev/null; then
    echo "yay is needed to look packages up in the AUR. Install it first." >&2
    exit 1
fi

echo "Tip: run 'sudo pacman -Sy' first so the sync databases are current."
echo ""

declare -A IN_REPO=()
while IFS= read -r name; do
    IN_REPO["$name"]=1
done < <(pacman -Slq)

mapfile -t PACKAGES < <(cat "${LISTS[@]}" | clean_list)

repo_count=0
aur_count=0
missing=()

for pkg in "${PACKAGES[@]}"; do
    if [[ -n "${IN_REPO[$pkg]:-}" ]]; then
        repo_count=$((repo_count + 1))
    elif yay -Si "$pkg" &>/dev/null; then
        aur_count=$((aur_count + 1))
    else
        missing+=("$pkg")
    fi
done

echo "Checked ${#PACKAGES[@]} unique packages."
echo "  in sync repos : $repo_count"
echo "  found via yay : $aur_count (AUR)"
echo "  NOT FOUND     : ${#missing[@]}"

if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    echo "Not found (renamed, removed, or a virtual name that is only a 'provides'):"
    printf '  %s\n' "${missing[@]}"
    echo ""
    echo "For each one try:  yay -Ss <part-of-name>   or   pacman -F <file>"
    exit 1
fi
