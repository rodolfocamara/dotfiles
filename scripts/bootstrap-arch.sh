#!/usr/bin/env bash
# Optional bootstrap for Arch: pacman + yay + AUR. Run manually (not via chezmoi run_once).
# Usage: from repo root, ./scripts/bootstrap-arch.sh
# Requires: CHEZMOI_SOURCE_DIR or run from repo root.

set -euo pipefail

# Detect Arch (ID=arch or ID_LIKE contains arch)
if [[ ! -f /etc/os-release ]]; then
    echo "Not a Linux with os-release"
    exit 0
fi
source /etc/os-release
if [[ "$ID" != "arch" && "${ID_LIKE:-}" != *arch* ]]; then
    echo "Not Arch Linux"
    exit 0
fi

# Resolve repo root
REPO_ROOT="${CHEZMOI_SOURCE_DIR:-}"
if [[ -z "$REPO_ROOT" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
AUR_LIST="$REPO_ROOT/packages/aur.txt"

# Log
LOG="$HOME/.bootstrap.$(date +%F).log"
exec > >(tee -a "$LOG") 2>&1
echo "=== $(date) bootstrap-arch ==="

# Internet
curl -fsS --connect-timeout 5 https://archlinux.org >/dev/null || { echo "No internet"; exit 1; }

# Pacman lock
while fuser /var/lib/pacman/db.lck >/dev/null 2>&1; do sleep 2; done

# Pacman — delega para não duplicar a resolução de perfil (base +
# pacman.<profile>.txt). Ver docs/machine-profiles.md.
CHEZMOI_SOURCE_DIR="$REPO_ROOT" "$REPO_ROOT/scripts/install-packages.linux-arch.sh"

# Yay (only if missing)
if ! command -v yay >/dev/null 2>&1; then
    echo "Installing yay..."
    tmp_yay=$(mktemp -d)
    trap "rm -rf $tmp_yay" EXIT
    git clone https://aur.archlinux.org/yay-bin.git "$tmp_yay"
    (cd "$tmp_yay" && makepkg -si --noconfirm) || (cd "$tmp_yay" && makepkg -si --noconfirm)
fi

# AUR
if [[ -f "$AUR_LIST" ]]; then
    aur_pkgs=$(grep -Ev '^(#|$)' "$AUR_LIST")
    if [[ -n "$aur_pkgs" ]]; then
        echo "$aur_pkgs" | yay -S --noconfirm --needed - || true
    fi
fi

echo "Bootstrap done. Log: $LOG"
