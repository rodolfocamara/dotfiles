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
packages/                        per-OS package lists (+ per-profile on Arch)
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

## Network runbooks

DNS goes out over TLS (Quad9, strict), the router's DNS is ignored, the Wi-Fi
MAC is per-network stable, and the VPN is split-tunnel. Each of those has a
failure mode that is not obvious six months later — a captive portal that will
not load, a VPN that kills the internet, an `AUTH_FAILED` that is not the
password you think it is.

Symptom → diagnosis → command: [docs/runbooks-rede.md](docs/runbooks-rede.md).

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

## External displays on NVIDIA (Linux)

Two unrelated failures that both show up as a black screen.

An external display that powers on but never gets an image, while KDE still
reports it `connected` and `enabled`, is `nvidia_drm` losing the modeset race
on hotplug. Cycling the mode forces a fresh one:

```fish
fix-monitor              # every enabled external display
fix-monitor --top        # only the upper external display
fix-monitor --dry-run    # just print what it would run
```

On the KDE machine, a user service watches both screen unlock and a real
system resume, then repairs `HDMI-A-1` and reconnects the MX Master 3S
automatically after a short settling delay. It is deployed and enabled by
`chezmoi apply`:

```bash
systemctl --user status fix-monitor-after-resume.service
journalctl --user -u fix-monitor-after-resume.service
```

The mouse recovery preserves its existing bond. It tries a normal connection
first and only power-cycles the Bluetooth controller if BlueZ is stuck; it
never removes or re-pairs the device. See
[docs/bluetooth-mouse.md](docs/bluetooth-mouse.md).

A black screen after a *real S3 resume* is a different bug:
`nvidia-suspend.service` ships disabled, so nothing writes VRAM out before S3
even though the driver was told to preserve it.

```bash
./scripts/setup-nvidia-sleep.sh
```

See [docs/nvidia-displays.md](docs/nvidia-displays.md) — it also covers how to
tell the two apart with `ddcutil` before touching anything.

After Limine/Snapper package upgrades, migrate the deprecated enrollment
commands to the package-provided pre/post hooks with:

```bash
./scripts/setup-limine-snapper.sh
```

## Bitwarden desktop ↔ Brave (Linux)

The desktop app writes the Native Messaging manifest only for Firefox, Chrome,
Chromium and Edge — Brave is not on its Linux list, and no Chromium browser
reads another one's `NativeMessagingHosts/`. Result: the extension keeps asking
for the master password even with the desktop app unlocked next to it.

`chezmoi apply` copies the manifest the app itself wrote into Brave's directory,
so `path` and `allowed_origins` follow Bitwarden upgrades on their own.

```bash
cat ~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.8bit.bitwarden.json
```

Restart Brave fully afterwards — the host list is read at browser startup. The
desktop app also has to stay running (tray), or there is no socket to talk to.
See [docs/bitwarden-brave.md](docs/bitwarden-brave.md).

## Battery charge cap (Legion / IdeaPad)

This is not a ThinkPad: there is no `charge_control_end_threshold`, so there is
no "stop at 80%". The EC offers an on/off conservation mode with a
firmware-defined cap, exposed by `ideapad_laptop` as `conservation_mode`.

A udev rule re-applies it on every boot and hands the attribute to `wheel`, so
toggling needs no sudo:

```bash
battery-conservation           # state + health + cycle count
battery-conservation off       # lasts until the next boot, by design
```

Installed by `./scripts/install-etc.sh` (skipped on machines without the
attribute). See [docs/battery.md](docs/battery.md) — it also records why the
popular AUR Legion toolkit is a trap (it blacklists the very driver that makes
this work) and what the serious alternative would buy you.

## Useful flags

```bash
chezmoi apply -n -v          # dry-run with diff
chezmoi diff                 # what would change
chezmoi status               # what differs between source and home
```
