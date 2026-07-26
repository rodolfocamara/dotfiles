#!/usr/bin/env bash
# Install pacman packages on Arch.
#
# Lê packages/pacman.txt (base) mais packages/pacman.<profile>.txt, quando esse
# existir. O perfil é o mesmo conceito do .chezmoiignore: numa máquina KDE o
# stack do Hyprland não é instalado. Ver docs/machine-profiles.md.
#
#   ./scripts/install-packages.linux-arch.sh --dry-run   # só mostra o que faria
#
# scripts/ é ignorado pelo chezmoi, então este script roda na mão e
# CHEZMOI_SOURCE_DIR normalmente não existe — daí o fallback pelo próprio path.

[[ "$(uname -s)" != "Linux" ]] && exit 0
command -v pacman >/dev/null 2>&1 || exit 0

set -euo pipefail

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

source_dir="${CHEZMOI_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Mesma ordem de decisão do .chezmoiignore: o que está no .chezmoidata.toml
# ganha; sem ele, quem tem o binário do Hyprland recebe o stack.
resolve_profile() {
    [[ -n "${DOTFILES_PROFILE:-}" ]] && { echo "$DOTFILES_PROFILE"; return; }

    local data_file="$source_dir/.chezmoidata.toml"
    if [[ -f "$data_file" ]]; then
        local from_toml
        from_toml=$(sed -n 's/^[[:space:]]*profile[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
            "$data_file" | head -1)
        [[ -n "$from_toml" ]] && { echo "$from_toml"; return; }
    fi

    command -v Hyprland >/dev/null 2>&1 && echo hyprland || echo generic
}

profile=$(resolve_profile)

base_file="$source_dir/packages/pacman.txt"
[[ ! -f "$base_file" ]] && { echo "Missing $base_file"; exit 1; }

files=("$base_file")
profile_file="$source_dir/packages/pacman.$profile.txt"
[[ -f "$profile_file" ]] && files+=("$profile_file")

list=$(grep -hEv '^[[:space:]]*(#|$)' "${files[@]}")
[[ -z "$list" ]] && { echo "No packages in ${files[*]}"; exit 0; }

echo "Profile: $profile"
for f in "${files[@]}"; do echo "  + ${f#"$source_dir"/}"; done

if (( dry_run )); then
    echo "--- would install ($(echo "$list" | wc -l) packages) ---"
    echo "$list"
    exit 0
fi

while fuser /var/lib/pacman/db.lck >/dev/null 2>&1; do sleep 2; done

echo "Installing packages..."
echo "$list" | sudo pacman -Syu --needed --noconfirm -

echo "Arch package installation complete."
