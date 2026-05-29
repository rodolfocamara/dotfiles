# Dotfiles

Cross-platform dev environment managed by [chezmoi](https://chezmoi.io/).

| Platform | Stack |
|---|---|
| **Windows** | PowerShell, Windows Terminal, AutoHotkey, AltSnap |
| **Arch Linux (Hyprland)** | waybar, wofi, kitty, OpenVPN + systemd-resolved |
| **Linux / WSL** | zsh, starship, zoxide, fzf, eza, bat, ripgrep |

## Install (fresh machine)

Source dir is set to this clone — no duplication.

```bash
# 1. Install chezmoi
# Windows:  winget install chezmoi
# Arch:     sudo pacman -S chezmoi
# Debian:   sudo apt install chezmoi -y

# 2. Clone the repo where you want it
git clone https://github.com/r-camara/dotfiles ~/Repos/dotfiles

# 3. Point chezmoi at this clone
mkdir -p ~/.config/chezmoi
echo 'sourceDir = "~/Repos/dotfiles"' > ~/.config/chezmoi/chezmoi.toml

# 4. Apply
chezmoi apply -v

# 5. /etc targets (OpenVPN, polkit) — Linux only
sudo chezmoi apply -v
```

## Daily workflow

```bash
# Edit in the repo, then deploy
vim ~/Repos/dotfiles/dot_zshrc
cma                          # alias for: chezmoi apply

# Or capture changes you made directly in $HOME back into the repo
chezmoi re-add ~/.zshrc

# Pull updates from GitHub
cd ~/Repos/dotfiles && git pull && cma
```

## Layout

```
dot_*           --> ~/           shell, git, envrc
dot_config/     --> ~/.config/   starship, hypr, waybar, kitty
apps/           --> Windows-only (PowerShell, Windows Terminal)
etc/            --> /etc/        system files (sudo apply)
packages/                        per-OS package lists
scripts/                         setup helpers
docs/                            guides
```

## Per-OS package install

```bash
# Windows
winget import packages/winget-packages.windows.txt

# Arch
./scripts/bootstrap-arch.sh

# Debian / Ubuntu / WSL
xargs sudo apt install -y < packages/apt-packages.linux-generic.txt
```

## ble.sh on Git Bash (Windows)

`dot_bashrc` sources [ble.sh](https://github.com/akinomyoga/ble.sh) — fish-like autosuggestions, syntax highlighting, and completion for bash. No-op if not installed.

```bash
# In Git Bash (Windows)
mkdir -p ~/.local/{share,tmp} && cd ~/.local/tmp
curl -L -o ble.tar.xz https://github.com/akinomyoga/ble.sh/releases/download/v0.4.0-devel3/ble-0.4.0-devel3-2.tar.xz
tar -xf ble.tar.xz
cp -r ble-*/. ~/.local/share/blesh/
rm -rf ble-* ble.tar.xz
```

Cost: ~80ms added to Git Bash startup.

## Encrypted files (age)

```bash
# First time: create key
age-keygen -o ~/.config/chezmoi/age.txt

# Encrypt a sensitive file under management
chezmoi add --encrypt /etc/openvpn/client/client.conf
```

See [docs/openvpn.md](docs/openvpn.md) for VPN setup.

## Useful flags

```bash
chezmoi apply -n -v          # dry-run with diff
chezmoi diff                 # what would change
chezmoi status               # what differs between source and home
```
