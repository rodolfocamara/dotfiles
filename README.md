# Dotfiles

Cross-platform dev environment managed by [chezmoi](https://chezmoi.io/).

## What's included

| Platform | Stack |
|---|---|
| **Windows** | PowerShell, Windows Terminal |
| **Arch Linux** | Hyprland + waybar + wofi, kitty, OpenVPN + systemd-resolved |
| **Generic Linux** | zsh, starship, direnv, common CLI tools |

## Quick start

```bash
# 1. Install chezmoi
# Windows:  winget install chezmoi
# Arch:     sudo pacman -S chezmoi
# Debian:   sudo apt install chezmoi -y

# 2. Init and apply
chezmoi init https://github.com/uranows/dotfiles.git
chezmoi apply -v

# 3. For /etc targets (OpenVPN, polkit)
sudo chezmoi apply -v
```

## Repository structure

```
dot_*                    --> ~/           Shell configs, .gitconfig, .envrc
dot_config/              --> ~/.config/   App configs (starship, hypr, waybar, kitty, etc.)
apps/                    --> (mapped)     Windows-only (terminal, pwsh)
etc/                     --> /etc/        System files (OpenVPN, polkit) - requires sudo
packages/                                OS-specific package lists
scripts/                                 Setup and install scripts
docs/                                    Guides (OpenVPN, waybar themes)
```

## Windows setup

```powershell
# Install packages
winget import packages/winget-packages.windows.txt
```

## Arch Linux (Hyprland)

```bash
# Optional: full bootstrap (pacman + yay + AUR)
./scripts/bootstrap-arch.sh

# Monitor config: edit ~/.config/hypr/hyprland.conf
# List monitors: hyprctl monitors
# List keyboards: hyprctl devices
```

See [docs/openvpn.md](docs/openvpn.md) for encrypted VPN config with age.

## Updating configs

**Workflow:** edit the source files in this repo, then deploy.

```bash
# Edit and apply
chezmoi edit ~/.zshrc        # opens the source file
chezmoi apply -v             # deploys changes

# Or edit directly in the repo and apply
vim ~/Repos/dotfiles/dot_zshrc
chezmoi apply -v

# Add a new file to management
chezmoi add ~/.config/new-app/config.toml
```

## Encrypted files

Uses [age](https://github.com/FiloSottile/age) for encrypting sensitive configs (e.g. OpenVPN client.conf).

```bash
# Setup: create age key
age-keygen -o ~/.config/chezmoi/age.txt

# Add encrypted file
chezmoi add --encrypt /etc/openvpn/client/client.conf
```

## Testing locally

Point chezmoi source to your clone instead of `~/.local/share/chezmoi`:

```bash
# Option A: symlink
ln -sf ~/Repos/dotfiles ~/.local/share/chezmoi

# Option B: set in .chezmoidata.toml (gitignored)
echo 'sourceDirOverride = "/home/rcamara/Repos/dotfiles"' > .chezmoidata.toml
chezmoi apply -v
```

Dry-run: `chezmoi apply -n -v`
