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

# Os manifests do AUR seguem o mesmo perfil dos manifests do pacman. Ficam
# separados porque o pacman não instala do AUR: precisa de um helper, e numa
# máquina sem helper o resto da lista ainda deve ser instalado normalmente.
aur_files=()
aur_file="$source_dir/packages/aur.txt"
[[ -f "$aur_file" ]] && aur_files+=("$aur_file")
profile_aur_file="$source_dir/packages/aur.$profile.txt"
[[ -f "$profile_aur_file" ]] && aur_files+=("$profile_aur_file")
aur_list=""
(( ${#aur_files[@]} > 0 )) && aur_list=$(grep -hEv '^[[:space:]]*(#|$)' "${aur_files[@]}" || true)

aur_helper=""
for h in paru yay; do
    command -v "$h" >/dev/null 2>&1 && { aur_helper="$h"; break; }
done

echo "Profile: $profile"
for f in "${files[@]}"; do echo "  + ${f#"$source_dir"/}"; done
if [[ -n "$aur_list" ]]; then
    for f in "${aur_files[@]}"; do echo "  + ${f#"$source_dir"/}"; done
    echo "    via ${aur_helper:-nenhum helper}"
fi

if (( dry_run )); then
    echo "--- would install ($(echo "$list" | wc -l) packages) ---"
    echo "$list"
    if [[ -n "$aur_list" ]]; then
        echo "--- AUR ($(echo "$aur_list" | wc -l) packages) ---"
        echo "$aur_list"
    fi
    exit 0
fi

while fuser /var/lib/pacman/db.lck >/dev/null 2>&1; do sleep 2; done

echo "Installing packages..."
echo "$list" | sudo pacman -Syu --needed --noconfirm -

# O helper roda como você, sem sudo — ele eleva sozinho só na hora de instalar
# o pacote já construído. Com sudo, o build aconteceria como root.
if [[ -n "$aur_list" ]]; then
    if [[ -z "$aur_helper" ]]; then
        echo "Nenhum helper de AUR (paru/yay) — pulando: $(echo "$aur_list" | tr '\n' ' ')"
    else
        echo "Installing AUR packages with $aur_helper..."
        # shellcheck disable=SC2086
        $aur_helper -S --needed --noconfirm $aur_list
    fi
fi

echo "Arch package installation complete."
