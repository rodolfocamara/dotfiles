#!/usr/bin/env bash
# Verifica se tun0 (OpenVPN) está ativo
if ip link show tun0 &>/dev/null; then
  echo '{"text": "\uf023", "tooltip": "VPN conectada (tun0)", "class": "connected"}'
else
  echo '{"text": "\uf09c", "tooltip": "VPN desconectada", "class": "disconnected"}'
fi
