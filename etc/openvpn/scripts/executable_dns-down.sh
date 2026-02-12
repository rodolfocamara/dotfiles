#!/usr/bin/env bash
set -euo pipefail

IFACE="${dev:-${1:-tun0}}"
resolvectl revert "$IFACE" || true
resolvectl flush-caches || true
