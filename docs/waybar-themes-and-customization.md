# Waybar – temas e customização

O que você pediu: mínimo, pouco uso de recurso, animações ok; workspaces + apps abertos + data/hora + sistema (cpu/mem/bluetooth/rede); sem música; barra à **direita** (ultrawide) ou em baixo (costume Windows); fácil de usar.

---

## O que é Niri?

**Niri** é um compositor Wayland em Rust, tipo “tiling com rolagem”: as janelas ficam em colunas numa faixa horizontal que pode ser rolada (em vez de redimensionar as janelas ao abrir novas). É uma **alternativa** ao Hyprland/Sway: outro gerenciador de janelas. Os dotfiles do Sudhboi são feitos para **Niri**; como você usa **Hyprland**, a gente troca os módulos `niri/workspaces` e `niri/window` por `hyprland/workspaces` e `hyprland/window`.

---

## 1) Order of preference (easiest → more work)

### 1º – Sudhboi/niri-rice-dotfiles (`.config/waybar`)

- **Easiest to “install”:** only 2 files: `config.jsonc` + `style.css`. Copy into `~/.config/waybar/`.
- **Catch:** written for **Niri** (`niri/workspaces`, `niri/window`). You use **Hyprland**, so you must:
  - Replace `niri/workspaces` → `hyprland/workspaces`
  - Replace `niri/window` → `hyprland/window`
  - Remove or replace Niri-only modules: `custom/wallpaper` (niri), `custom/appmenu` (niri toggle-overview), `custom/idlekiller` (hypridle) if you use it.
- **Good for you:** bar already on **left** (`"position": "left"`, `"width": 40`) – easy to flip to **right**; vertical layout fits ultrawide; clean structure; drawer groups with transitions (animations); no music/todo/countdown.
- **Deps:** waybar, Nerd Fonts (icons). No extra scripts.

**Verdict:** Best base for “minimal + right bar + animations” if you adapt it to Hyprland and drop Niri-specific bits.

---

### 2º – Harsh-bin/waybar-config

- **Install:** `install.sh` copies config + styles + scripts into `~/.config/waybar/`.
- **Pros:** bar on **bottom** (`"position": "bottom"`) – very Windows-like; `wlr/taskbar` for running apps; launcher (wofi) on click; power menu; keyboard state (Caps).
- **Cons:** Depends on **Foot** for countdown; **todo** and **countdown** modules and scripts; **music** (you said no); many `custom/*` app shortcuts (chrome, terminal, code, music, thunar). Heavier and more to maintain.
- **For you:** You can strip music, todo, countdown and use only: launcher, taskbar, cpu/mem, network, bluetooth, tray, clock, power group. Still need to fix script paths (e.g. lock, power) for your system.

**Verdict:** Good if you want **bottom** bar and don’t mind deleting modules and adjusting scripts.

---

### 3º – saatvik333/niri-dotfiles

- **Install:** Full Niri rice (install script, 15–30 min): Niri, Waybar, Fish, Rofi, Wallust, etc. Not “just Waybar”.
- **Cons:** Niri-only; whole-dotfiles install; many themes (Wallust) and tools. Overkill if you only want a nice Waybar on Hyprland.

**Verdict:** Skip unless you plan to switch to Niri.

---

### 4º – niksingh710/gdots

- **Install:** Hyprland + **pywal16** + stow; Waybar colors come from a generated CSS (pywal). Many deps (gradience, kvantum, rofi, swaync, etc.).
- **Cons:** Theming tied to pywal; Waybar scripts in `~/.local/bin` and waybar-specific scripts; more moving parts. Not “drop-in” Waybar.

**Verdict:** Only if you already want a pywal-based, full Hyprland rice.

---

## 2) Other tools worth looking at (and why)

| Tool | Why |
|------|-----|
| **wlr/taskbar** (in Waybar) | Shows running apps by window; click to focus/minimize. Very Windows-like. |
| **hyprland/workspaces** | Desktops 1–9 (or 10); click to switch. Organize by workspace. |
| **hyprland/window** | Current window title. Good for “what’s running” at a glance. |
| **Rofi or Wofi** | You already use Wofi for app menu; can add a “power menu” (logout/reboot/shutdown) script if you want. |
| **swaync / mako / dunst** | Notifications. Swaync is more “panel-like”; mako/dunst lighter. |
| **hyprlock / swaylock** | Lock screen. Fits “power” area in bar. |
| **brightnessctl / wpctl** | You already use for brightness/volume; Waybar can show backlight/pulseaudio. |

No need for music addons (playerctl in bar, etc.) if you don’t use them.

---

## 3) Customization sketch (idea to implement in Cursor)

Goal: **minimal** bar, **right** side (ultrawide), or **bottom** (Windows-like); workspaces + running apps + date/time + cpu/mem/network/bluetooth; optional animations; no music; low resource.

### Option A – Bar on the **right** (vertical)

- **position:** `"right"`  
- **width:** e.g. `42`  
- **margin-right / margin-left:** e.g. `4`  
- **Modules (top → bottom or logical order):**
  - **Power / menu:** one icon (e.g. Super) → wofi; optional power drawer (lock, logout, reboot, shutdown).
  - **hyprland/workspaces:** `format: "{name}"` or icons; click to switch.
  - **hyprland/window:** current window title (optional `rotate: 270` for vertical text).
  - **wlr/taskbar:** running apps (icons); click = activate.
  - **network:** wifi/ethernet/disconnected.
  - **bluetooth:** connected/disconnected.
  - **cpu** + **memory:** e.g. `"format": "{}%"`.
  - **tray:** system tray.
  - **clock:** `"{:%H:%M}"` and tooltip with date.

Use **group** + **drawer** (with `transition-duration`) for power and maybe for “system” (cpu/memory/network/bluetooth) so the bar stays narrow and expands on hover – gives a minimal look and light animations.

### Option B – Bar on the **bottom** (Windows-like)

- **position:** `"bottom"`  
- **height:** e.g. `36`  
- **modules-left:** e.g. launcher (wofi), **hyprland/workspaces**, **hyprland/window**.  
- **modules-center:** **wlr/taskbar** (running apps).  
- **modules-right:** cpu, memory, network, bluetooth, tray, clock, (optional power drawer).

Same modules as now, just order and styling; no extra scripts if you don’t add power menu / custom launcher.

### Style (both options)

- **Nord-like (you already use):** `#2e3440` background, `#eceff4` text, `#434c5e` active workspace, `#88c0d0` hover/active accent.
- **Animations:** `transition: background-color 0.2s ease, color 0.2s ease` on modules; Waybar `drawer` `transition-duration` for slide in/out.
- **Font:** JetBrainsMono Nerd Font (icons + text); size 12–13px.
- **Padding:** e.g. `padding: 4px 10px` on modules; `border-radius: 6px` for “buttons”.

### What to take from each repo

- **From Sudhboi (niri-rice):** vertical layout, `position`/`width`/margins, **group**+**drawer** usage, pulseaudio/backlight/battery format (if you want them). Then replace niri → hyprland and remove niri-only custom modules.
- **From Harsh-bin:** bottom bar layout, **wlr/taskbar** config, launcher on-click (`wofi --show drun`), and power group idea (you can replace their scripts with simple `systemctl`/`hyprlock`/logout commands).

### Minimal config idea (right bar, no extra scripts)

- Left (top of bar): custom/launcher (icon → wofi).
- Then: hyprland/workspaces.
- Then: hyprland/window.
- Then: wlr/taskbar.
- Then: network, bluetooth, cpu, memory.
- Then: tray, clock.

All in one `config.jsonc`; one `style.css` with the colors and transitions above. No pywal, no countdown/todo/music. You can add a small “power” group with lock/logout/reboot/shutdown (each `custom/` with `on-click` to a command) later if you want.

---

## 4) Next step in Cursor

1. Choose **right** or **bottom** bar.
2. Copy Sudhboi’s `config.jsonc` and `style.css` (or Harsh’s for bottom) into your `dot_config/waybar/`.
3. In `config`: replace niri → hyprland; set `position` to `"right"` or `"bottom"`; remove niri-only and music/todo/countdown; keep cpu, memory, network, bluetooth, tray, clock, wlr/taskbar, hyprland/workspaces, hyprland/window.
4. In `style.css`: adjust colors to your Nord palette; add padding/border-radius and transitions.
5. Test with `waybar` (or restart Waybar from Hyprland).
6. Tweak formats (e.g. clock, cpu, memory) to taste.

If you tell me “right” or “bottom” and whether you want a power drawer (lock/logout/reboot/shutdown), I can turn this into concrete `config` + `style.css` snippets for your repo.

---

## Barra à direita + power drawer (aplicado no repo)

No seu `dot_config/waybar/` foi configurado:

- **position:** `right` (barra na direita da tela).
- **Em cima:** ícone do menu (Super) → abre o wofi.
- **Workspaces** (hyprland/workspaces) e **janela atual** (hyprland/window).
- **wlr/taskbar:** ícones dos apps abertos; clique = ativar/minimizar.
- **Rede, bluetooth, cpu, memória, tray, relógio.**
- **Power drawer:** grupo que abre ao clicar; dentro: Bloquear (hyprlock), Sair (hyprctl dispatch exit), Reiniciar, Desligar.

**Dependências:** waybar, hyprlock (já no seu pacman.txt). Para o taskbar funcionar, o Waybar precisa ter suporte a `wlr/taskbar` (normal no Hyprland).

Depois de aplicar com chezmoi, reinicie o Waybar (Super+Shift+R no Hyprland ou `killall waybar && waybar &`).

---

## Customizar a barra (config + style.css)

### Cores e estilo (style.css)

No topo de `style.css` estão as variáveis CSS. Altere só ali para mudar o tema:

| Variável       | Uso              | Nord (atual) |
|----------------|------------------|--------------|
| `--waybar-bg`  | Fundo da barra   | `#2e3440`    |
| `--waybar-fg`  | Texto geral      | `#eceff4`    |
| `--module-bg`  | Fundo dos módulos| `#3b4252`    |
| `--module-active` | Workspace/task ativo | `#434c5e` |
| `--module-hover`  | Hover            | `#4c566a`    |
| `--accent`     | Hover nos ícones | `#88c0d0`    |
| `--accent-fg`  | Texto no hover   | `#2e3440`    |
| `--radius`     | Bordas arredondadas | `6px`     |
| `--font-size`  | Tamanho do texto | `12px`     |

Exemplo tema escuro mais suave: `--waybar-bg: #1e1e2e;` e `--accent: #cba6f7;`.

### Config (JSON)

O `config` está em JSON formatado (um campo por linha) para ser fácil editar em `dot_config/waybar/config`:

- **Barra à esquerda:** `"position": "left"`.
- **Barra em baixo (estilo Windows):** `"position": "bottom"`, `"width": 0`, `"height": 36`, e trocar `modules-left` por `modules-left` / `modules-center` / `modules-right` conforme quiseres (ver doc Waybar).
- **Largura:** `"width": 42` (aumentar se quiseres mais espaço para texto).
- **Módulos:** a ordem em `modules-left` é de cima para baixo na barra vertical.

### Módulos opcionais (adicionar em config + style.css)

- **Brilho (laptop):** em `config`, em `modules-left` (ex.: antes de `clock`), acrescentar `"backlight"` e depois um bloco:
  `"backlight": { "format": "{percent}%", "tooltip": true }`.
  No `style.css` acrescentar `#backlight` às regras dos outros módulos e ao hover.

- **Bateria:** `"battery": { "format": "{capacity}%", "format-charging": "{capacity}% +", "interval": 30 }` e estilos para `#battery`.

- **Volume (PulseAudio):** `"pulseaudio": { "format": "{volume}%", "format-muted": "mute", "on-click": "pactl set-sink-mute @DEFAULT_SINK@ toggle" }` e estilos para `#pulseaudio`.

Depois de alterar, `killall waybar && waybar &` ou recarregar a sessão.
