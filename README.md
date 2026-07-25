# Dotfiles

Cross-platform dev environment managed by [chezmoi](https://chezmoi.io/).

| Platform | Stack |
|---|---|
| **Windows** | PowerShell, Windows Terminal, AutoHotkey |
| **Arch Linux (Hyprland)** | fish, waybar, wofi, kitty, OpenVPN + systemd-resolved |
| **Linux / WSL** | zsh, starship, zoxide, fzf, eza, bat, ripgrep |

## Install (fresh machine)

Source dir is set to this clone — no duplication.

```bash
# 1. Install chezmoi
# Windows:  winget install chezmoi
# Arch:     sudo pacman -S chezmoi
# Debian:   sudo apt install chezmoi -y

# 2. Clone the repo where you want it
git clone https://github.com/rodolfocamara/dotfiles ~/Repos/dotfiles

# 3. Point chezmoi at this clone
mkdir -p ~/.config/chezmoi
echo 'sourceDir = "~/Repos/dotfiles"' > ~/.config/chezmoi/chezmoi.toml

# 4. Apply
chezmoi apply -v

# 5. /etc files (OpenVPN, polkit, wsl.conf) — Linux only.
# NOT chezmoi: its destDir is always $HOME, so the etc/ tree would land in
# ~/etc/. Run as yourself; the script sudos only where it writes.
./scripts/install-etc.sh --dry-run
./scripts/install-etc.sh
```

## Daily workflow

```bash
# Edit in the repo, then deploy
vim ~/Repos/dotfiles/dot_zshrc
cma                          # chezmoi apply — zsh alias, fish abbr

# Or capture changes you made directly in $HOME back into the repo
chezmoi re-add ~/.zshrc

# Pull updates from GitHub
cd ~/Repos/dotfiles && git pull && cma
```

`cma` and the `g*` git shortcuts are defined once per shell: as aliases in
[dot_zshrc](dot_zshrc) and as abbreviations in
[dot_config/fish/config.fish](dot_config/fish/config.fish). fish is the login
shell on Arch/CachyOS, so keep the two in sync when adding a new one.

## Layout

```
dot_*           --> ~/           shell, git, envrc
dot_config/     --> ~/.config/   fish, starship, hypr, waybar, kitty, zed, searxng, quadlets
apps/           --> Windows-only (PowerShell, Windows Terminal)
AppData/        --> %APPDATA%    Windows-only targets (Zed)
.chezmoitemplates/               shared content included by per-OS targets (Zed)
etc/            --> /etc/        via scripts/install-etc.sh (not a chezmoi target)
packages/                        per-OS package lists
scripts/                         setup helpers
docs/                            guides
```

## Machine profiles

OS is not enough: both Linux machines run different desktops (Hyprland vs KDE),
so one machine's desktop config is dead weight on the other. Set the profile in
`.chezmoidata.toml` at the source root — per machine, not committed:

```toml
profile = "hyprland"   # or "kde", "generic"
```

Without the file it auto-detects from the compositor binary. See
[docs/machine-profiles.md](docs/machine-profiles.md).

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

# Encrypt a file that lives in /etc. `chezmoi add` does not work for those —
# they are not chezmoi targets. Encrypt straight into the source tree:
age -e -r "$(age-keygen -y < ~/.config/chezmoi/age.txt)" \
    < plaintext > etc/openvpn/client/encrypted_client.conf.age
```

See [docs/openvpn.md](docs/openvpn.md) for VPN setup.

## Local search for agents (Linux)

SearxNG in a rootless podman quadlet, bound to `127.0.0.1:8888`, exposed to
Claude Code / Codex / OpenCode / Zed through one MCP server. No quota, no
per-query cost, `pt-BR` by default, and queries never leave the machine.

```bash
./scripts/setup-searxng.sh
```

See [docs/searxng.md](docs/searxng.md).

## Zed (VSCode-like, Linux + Windows)

Same Zed profile on both machines: VSCode keymap and layout (explorer/git on
the left, agent panel on the right), shared from `.chezmoitemplates/zed/` into
`~/.config/zed/` and `%APPDATA%\Zed\`.

Edit the template, not the target — the targets are one-line wrappers, so
`chezmoi re-add` does not work for them.

See [docs/zed.md](docs/zed.md).

## Useful flags

```bash
chezmoi apply -n -v          # dry-run with diff
chezmoi diff                 # what would change
chezmoi status               # what differs between source and home
```
