#!/usr/bin/env bash
# Cicla foco entre TODAS as janelas em TODOS os monitores.
# Uso: cycle-windows.sh next | prev
# Depende: jq (pacman -S jq)

dir="${1:-next}"
clients=$(hyprctl clients -j 2>/dev/null) || exit 0
[[ -z "$clients" || "$clients" == "[]" ]] && exit 0

if ! command -v jq &>/dev/null; then
  notify-send -t 2000 "Alt+Tab" "Instale jq: pacman -S jq" 2>/dev/null || true
  exit 1
fi

active=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty' 2>/dev/null) || true
# Ordem: por workspace id, depois posição (compatível com hyprctl -j)
mapfile -t addresses < <(echo "$clients" | jq -r 'sort_by(.workspace.id, .at[0], .at[1]) | .[].address' 2>/dev/null) || exit 0
n=${#addresses[@]}
[[ $n -eq 0 ]] && exit 0

idx=0
for i in "${!addresses[@]}"; do
  if [[ "${addresses[$i]}" == "$active" ]]; then idx=$i; break; fi
done

if [[ "$dir" == "prev" ]]; then
  idx=$(( (idx - 1 + n) % n ))
else
  idx=$(( (idx + 1) % n ))
fi

hyprctl dispatch focuswindow "address:${addresses[$idx]}"
hyprctl dispatch alterzorder top
