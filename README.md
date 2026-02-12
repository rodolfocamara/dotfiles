# My Dotfiles

Personal environment configurations (Linux & Windows) managed by [chezmoi](https://chezmoi.io/).

## Prerequisites

*   **Git:** Required.
*   **chezmoi:** Must be installed on the target machine.
    *   **Windows (PowerShell):**
        ```powershell
        winget install chezmoi
        ```
    *   **Linux (Debian/Ubuntu/WSL):**
        ```bash
        sudo apt update && sudo apt install chezmoi -y
        ```
    *   **Linux (Arch):**
        ```bash
        yay -S chezmoi-bin
        # or
        sudo pacman -S chezmoi
        ```

## Initial Setup

1.  **Initialize chezmoi:**
    ```bash
    chezmoi init https://github.com/uranows/dotfiles.git
    ```
    *(Alternatively, use `chezmoi init /path/to/local/clone` if you cloned manually).*\
    *(**Troubleshooting:** If `init` or subsequent commands fail unexpectedly, try clearing the chezmoi state and re-running `init`: `rm -rf ~/.config/chezmoi ~/.local/share/chezmoi`)*

2.  **First Apply:**
    ```bash
    chezmoi apply -v
    ```
    *   Installs packages via appropriate package manager (`apt`, `pacman`, `winget`).
    *   **Windows:** May require running from PowerShell **as Administrator**.

3.  **Configure Mappings (Important!):**
    *   The first `apply` creates `~/.config/chezmoi/chezmoi.toml`.
    *   Edit this file (`chezmoi edit ~/.config/chezmoi/chezmoi.toml`) to ensure paths for `apps/` directory files (Windows Terminal, PowerShell profile) are correct, especially on Windows. The template includes examples.
    *   Rerun `chezmoi apply -v` if mappings were adjusted.

## Common Commands

*   `chezmoi apply -v`: Apply changes from source to target.
*   `chezmoi update -v`: Pull latest changes from Git remote and apply.
*   `chezmoi edit <target_file>`: Edit a managed file (e.g., `chezmoi edit ~/.zshrc`).
*   `chezmoi add <target_file>`: Add a new file to be managed.

## OS-Specific Configuration

This repository supports multiple operating systems with automatic detection:

### Supported OS
- **Windows**: PowerShell, Windows Terminal, winget packages
- **Generic Linux**: Debian, Ubuntu, Mint, Pop!_OS, and other apt-based distributions (fallback)
- **Arch Linux**: pacman packages, specific Arch optimizations

### File Structure
```
scripts/
├── install-packages.windows.ps1      # Windows package installation
├── install-packages.linux-generic.sh  # Generic Linux (Debian/Ubuntu/etc)
├── install-packages.linux-arch.sh    # Arch: pacman from pacman.txt (run_once)
└── bootstrap-arch.sh                 # Arch: optional manual bootstrap (pacman + yay + AUR)

packages/
├── winget-packages.windows.txt       # Windows package list
├── apt-packages.linux-generic.txt    # Generic Linux package list
├── pacman.txt                        # Arch: pacman packages (one per line)
└── aur.txt                           # Arch: AUR-only packages (minimal)
```

### OS Detection Logic
Chezmoi automatically detects your system and selects the appropriate configuration:

1. **Windows**: Uses PowerShell and winget
2. **Arch Linux**: Detects `/etc/arch-release` and uses pacman
3. **Generic Linux**: Everything else uses apt-based package management (Debian, Ubuntu, Mint, etc.)

### Manual Override (Advanced)
If you need to override the OS detection for testing or debugging:

```bash
# Force specific OS configuration
CHEZMOI_OS=windows chezmoi apply -v
CHEZMOI_OS=linux chezmoi apply -v
```

### Arch Linux (Hyprland)

1. **Install git and chezmoi:** `sudo pacman -S git chezmoi` (or `yay -S chezmoi-bin`).
2. **Init and apply:** `chezmoi init https://github.com/uranows/dotfiles.git` then `chezmoi apply -v`.
3. **Optional bootstrap (manual):** From the repo source dir, run `./scripts/bootstrap-arch.sh` to install packages from `packages/pacman.txt`, yay if missing, and `packages/aur.txt`. Not run automatically on apply.
4. **Monitors:** In `~/.config/hypr/hyprland.conf`, see the commented monitor block. List names with `hyprctl monitors`, then add lines like `monitor=DP-1,1920x1080@60,0x0,1`. If Hyprland reports errors (e.g. `gestures:workspace_swipe`, `suppressevent`, `nofocus`), your file may have extra content from another setup — run `chezmoi apply -v` and overwrite the file with the repo version, or remove those deprecated/invalid options manually.
5. **Keyboard (per-device):** Default is US-INTL. For ABNT2 on laptop + US-INTL on external: run `hyprctl devices` to get device names, then in `~/.config/hypr/hyprland.conf` uncomment the `device { ... }` blocks and replace `<INTERNAL_KEYBOARD_NAME>` / `<EXTERNAL_KEYBOARD_NAME>`. Use `kb_layout = br`, `kb_variant = abnt2` for internal and `us`/`intl` for external.
6. **Timezone (GMT-3 São Paulo, document only — run manually if needed):**
   ```bash
   sudo timedatectl set-timezone America/Sao_Paulo
   sudo timedatectl set-ntp true
   ```

7. **OpenVPN + systemd-resolved (split DNS):** When using `openvpn-client@client` with pushed DNS, these dotfiles apply pushed DNS to the VPN interface via systemd-resolved. Split DNS uses the server-pushed domain (e.g. `dhcp-option DOMAIN`) plus `work.example.invalid`. **Encrypted client.conf:** the repo can manage `/etc/openvpn/client/client.conf` encrypted with age — see [docs/openvpn.md](docs/openvpn.md) for setup, `chezmoi edit`, and apply. If you manage `client.conf` yourself instead, add the following to your own `/etc/openvpn/client/client.conf` (or equivalent):
   - **Enable systemd-resolved:** `sudo systemctl enable --now systemd-resolved`. Ensure `/etc/resolv.conf` is the stub: `sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf` (if not already).
   - **Snippet for client.conf:**
     ```ini
     script-security 2
     up /etc/openvpn/scripts/dns-up.sh
     down /etc/openvpn/scripts/dns-down.sh
     down-pre
     up-restart
     pull-filter ignore "ip-win32"
     ```
   - **Apply /etc files (run with sudo):** `sudo chezmoi apply -v`
   - **Restart services:** `sudo systemctl restart polkit; sudo systemctl restart openvpn-client@client`
   - **Verify:** `resolvectl status tun0` (after VPN is up; should show DNS servers and domains for the VPN link).

   Chezmoi source paths for these files: `etc/openvpn/scripts/executable_dns-up.sh`, `etc/openvpn/scripts/executable_dns-down.sh`, `etc/polkit-1/rules.d/49-openvpn-resolved.rules` (targets set in `.chezmoi.toml`).

## Repository Structure Overview

*   **`home/`**: Maps directly to user's home (`~`). Uses `dot_` prefix for hidden files.
*   **`etc/`**: System files under `/etc` (OpenVPN scripts, polkit rules, encrypted client.conf). Applied with `sudo chezmoi apply`; targets defined in `.chezmoi.toml`.
*   **`docs/`**: Documentation (e.g. [openvpn.md](docs/openvpn.md) for encrypted client config).
*   **`apps/`**: Configs needing explicit path mapping in `chezmoi.toml` (e.g., Windows Terminal, PowerShell profile).
*   **`packages/`**: OS-specific package lists for different package managers.
*   **`scripts/`**: OS-specific installation scripts run by `apply`.
*   **`.chezmoiignore`**: Files/patterns ignored by chezmoi.
*   **`README.md`**: This file.
