#!/usr/bin/env bash
# This script installs packages on Debian-based Linux systems and generic Linux fallback
# It uses the packages list from the packages directory
# CHEZMOI_SOURCE_DIR is set by chezmoi

# Only proceed on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
    echo "Skipping Linux package installation on non-Linux host"
    exit 0
fi

set -euo pipefail

# Detect package manager and distribution
PACKAGE_MANAGER=""
DISTRO_NAME=""

if command -v apt-get >/dev/null 2>&1; then
    PACKAGE_MANAGER="apt"
    if [[ -f /etc/debian_version ]]; then
        DISTRO_NAME="Debian"
    elif [[ -f /etc/lsb-release ]]; then
        DISTRO_NAME="Ubuntu"
    else
        DISTRO_NAME="Debian-based"
    fi
elif command -v dnf >/dev/null 2>&1; then
    PACKAGE_MANAGER="dnf"
    DISTRO_NAME="Fedora/RHEL"
elif command -v yum >/dev/null 2>&1; then
    PACKAGE_MANAGER="yum"
    DISTRO_NAME="RHEL/CentOS"
else
    echo "No supported package manager found (apt, dnf, yum)"
    echo "Please install packages manually: zsh, starship, git, curl, eza, fzf, bat, ripgrep, fd, tldr"
    PACKAGE_MANAGER="none"
fi

echo "Detected: $DISTRO_NAME with $PACKAGE_MANAGER package manager"

# Handle different package managers
case $PACKAGE_MANAGER in
    "apt")
        # Path to APT packages list
        packages_file="$CHEZMOI_SOURCE_DIR/packages/apt-packages.linux-generic.txt"
        if [[ ! -f "$packages_file" ]]; then
            echo "APT package list not found: $packages_file"
            exit 1
        fi

        echo "Updating apt package lists..."
        sudo apt-get update

        echo "Installing apt packages from $packages_file..."
        grep -Ev '^(#|$)' "$packages_file" | xargs sudo apt-get install -y
        ;;
    "dnf"|"yum")
        echo "RHEL/Fedora system detected. Please install packages manually:"
        echo "- zsh, starship, git, curl, eza, fzf, bat, ripgrep, fd, tldr"
        echo "- build tools: gcc, cmake, openssl-devel"
        ;;
    "none")
        echo "No supported package manager found. Please install packages manually."
        exit 0
        ;;
esac

# Install Rust if not present
if ! command -v cargo >/dev/null 2>&1; then
    echo "Installing Rust and Cargo via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    # Criado pelo rustup na linha acima; não existe em tempo de análise.
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env" || true
fi

# Install Cargo packages
cargo_packages=("zoxide --locked" "gitui" "du-dust")
echo "Installing Cargo packages: ${cargo_packages[*]}"
for pkg in "${cargo_packages[@]}"; do
    # Cada entrada pode trazer flags junto ("zoxide --locked"), então o split
    # em palavras é intencional. Feito aqui de forma explícita, com read -ra,
    # em vez de depender do split implícito de uma expansão sem aspas.
    read -ra spec <<< "$pkg"
    cargo install "${spec[@]}" || echo "Warning: Failed to install cargo package '$pkg'"
done

# Fix bat -> batcat symlink if needed (Debian/Ubuntu specific)
if [[ "$PACKAGE_MANAGER" == "apt" ]]; then
    echo "Ensuring batcat is available as bat..."
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    fi
fi

echo "Linux package installation complete for $DISTRO_NAME."
