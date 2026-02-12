#!/usr/bin/env bash
# Set ownership and permissions for OpenVPN client config (root:network, 750 dir, 640 file).
# Only runs when executed as root (e.g. sudo chezmoi apply); no-op otherwise.
set -euo pipefail
[[ $(id -u) -eq 0 ]] || exit 0
DIR="/etc/openvpn/client"
CONF="${DIR}/client.conf"
[[ -d "$DIR" ]] || exit 0
chmod 750 "$DIR"
chown root:network "$DIR"
[[ -f "$CONF" ]] && { chmod 640 "$CONF"; chown root:network "$CONF"; }
