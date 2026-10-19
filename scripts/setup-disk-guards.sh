#!/usr/bin/env bash
# Instala só os limites de logs/pacotes, sem aplicar outros alvos de /etc.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dry_run=false
case "${1:-}" in
    '') ;;
    --dry-run) dry_run=true ;;
    *) echo "uso: $0 [--dry-run]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2
[[ $(uname -s) == Linux && -d /run/systemd/system ]] || { echo 'pulo (systemd ausente)'; exit 0; }
[[ $EUID -ne 0 ]] || { echo 'Execute como usuário, sem sudo.' >&2; exit 2; }
run() {
    $dry_run && printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    if ! $dry_run; then "$@"; fi
}
run sudo install -D -m 644 "$repo/etc/systemd/journald.conf.d/disk-maintenance.conf" /etc/systemd/journald.conf.d/disk-maintenance.conf
run sudo systemctl restart systemd-journald
if command -v paccache >/dev/null 2>&1 && systemctl cat paccache.timer >/dev/null 2>&1; then
    for unit in timer service; do
        run sudo install -D -m 644 "$repo/etc/systemd/system/paccache.$unit.d/disk-maintenance.conf" "/etc/systemd/system/paccache.$unit.d/disk-maintenance.conf"
    done
    run sudo systemctl daemon-reload
    run sudo systemctl enable paccache.timer
    run sudo systemctl restart paccache.timer
else
    echo 'pulo (paccache ausente)'
fi
