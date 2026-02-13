#!/usr/bin/env bash
# Power menu via wofi – toggle, posição per-monitor, fecha ao perder foco

# Toggle
if pgrep -x wofi >/dev/null; then
  pkill -x wofi
  exit 0
fi

# Calcula posição exata no monitor focado
eval "$(hyprctl monitors -j | jq -r '.[] | select(.focused) |
  "MW=\(.width) MH=\(.height) SC=\(.scale) MX=\(.x) MY=\(.y) RR=\(.reserved[2])"')"
LW=$(awk "BEGIN{printf \"%.0f\", $MW/$SC}")
LH=$(awk "BEGIN{printf \"%.0f\", $MH/$SC}")
PX=$((MX + LW - 180 - RR - 8))
PY=$((MY + LH - 160))

# Ajuste fino: move wofi sem animação assim que aparecer
(
  for _ in $(seq 1 30); do
    A=$(hyprctl clients -j | jq -r '.[] | select(.class=="wofi") | .address')
    if [[ -n "$A" ]]; then
      hyprctl setprop "address:$A" noanim 1 2>/dev/null
      hyprctl dispatch movewindowpixel "exact $PX $PY,address:$A" 2>/dev/null
      break
    fi
    sleep 0.02
  done
) &

# Fecha ao perder foco
(
  sleep 0.5
  while pgrep -x wofi >/dev/null; do
    [[ "$(hyprctl activewindow -j | jq -r '.class // empty')" != "wofi" ]] && { pkill -x wofi; break; }
    sleep 0.2
  done
) &

choice=$(printf '\uf023  Lock\n\uf2f5  Logout\n\uf2ea  Reboot\n\uf186  Sleep\n\uf011  Shutdown' | wofi \
  --dmenu --prompt "" \
  --width 180 --height 250 --lines 5 \
  --normal-window --hide-search --insensitive \
  --cache-file /dev/null)

case "$choice" in
  *Lock*)     hyprlock 2>/dev/null || swaylock -f ;;
  *Logout*)   hyprctl dispatch exit ;;
  *Reboot*)   systemctl reboot ;;
  *Sleep*)    systemctl suspend ;;
  *Shutdown*) systemctl poweroff ;;
esac
