# Dotfiles

Cross-platform dev environment managed by [chezmoi](https://chezmoi.io/).

## What's included

| Platform | Stack |
|---|---|
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
etc/                     --> /etc/        System files (OpenVPN, polkit) - requires sudo
packages/                                OS-specific package lists
scripts/                                 Setup and install scripts
docs/                                    Guides (OpenVPN, waybar themes)
```

## Windows tiling setup

Three-monitor layout: 2 stacked ultrawides + laptop on the right.

**Keybindings** (win key as modifier):

| Action | Binding |
|---|---|
| Focus window | `win + arrows` |
| Move window | `win + shift + arrows` |
| Resize window | `win + alt + arrows` |
| Switch workspace | `win + 1/2` or `win + ctrl + left/right` |
| Move to workspace | `win + shift + 1/2` |
| Focus monitor | `win + ctrl + shift + arrows` |
| Move to monitor | `win + ctrl + alt + arrows` |
| Open terminal | `win + X` |
| Open browser | `win + C` |
| Promote window | `win + Enter` |
| Toggle float | `win + T` |
| Toggle monocle | `win + F` |
| Close window | `win + Q` |
| Retile | `win + shift + E` |
| Flip layout | `win + shift + X` / `win + Y` |
| Reload config | `win + shift + R` |


**First-time Windows setup:**
```powershell
# Install packages
winget import packages/winget-packages.windows.txt

# Apply registry tweaks (disable snap assist, animations, auto-hide taskbar)
powershell -ExecutionPolicy Bypass -File scripts/setup-windows-tweaks.ps1
Stop-Process -Name explorer -Force
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

**Windows configs** (not managed by chezmoi apply):
```powershell
# Copy to Windows locations and reload
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
