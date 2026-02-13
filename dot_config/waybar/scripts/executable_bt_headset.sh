#!/usr/bin/env bash
# Bluetooth: só ícone centralizado; nome do dispositivo no tooltip
if ! command -v bluetoothctl &>/dev/null; then
  printf '{"text": "\uf293", "tooltip": "bluetoothctl não instalado", "class": "disabled"}\n'
  exit 0
fi
info=$(bluetoothctl info 2>/dev/null)
if echo "$info" | grep -q "Connected: yes"; then
  name=$(echo "$info" | grep "Name:" | head -1 | sed 's/.*Name: //')
  printf '{"text": "\uf293", "tooltip": "%s (conectado)", "class": "connected"}\n' "$name"
else
  printf '{"text": "\uf293", "tooltip": "Desconectado", "class": "disconnected"}\n'
fi
