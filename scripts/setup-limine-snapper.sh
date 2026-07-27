#!/usr/bin/env bash
# Migra a integração Limine/Snapper das opções COMMANDS_* obsoletas para os
# hooks fornecidos pelo próprio limine-mkinitcpio-hook.

set -euo pipefail

config=/etc/limine-snapper-sync.conf
backup=/etc/limine-snapper-sync.conf.pre-hooks-migration.bak
pre_hook=/etc/boot/hooks/pre.d/10-limine-reset-enroll
post_hook=/etc/boot/hooks/post.d/90-limine-enroll-config

[[ $(uname -s) == Linux ]] || { echo "Linux only."; exit 1; }
[[ $(id -u) -ne 0 ]] || {
    echo "Rode como usuário normal; o script usa sudo só para /etc." >&2
    exit 1
}

for hook in "$pre_hook" "$post_hook"; do
    if ! sudo test -x "$hook"; then
        echo "Hook obrigatório ausente ou não executável: $hook" >&2
        exit 1
    fi
done

if ! sudo grep -qE '^COMMANDS_(BEFORE|AFTER)_SAVE=' "$config"; then
    echo "Limine/Snapper já usa os hooks atuais."
    exit 0
fi

if ! sudo test -e "$backup"; then
    sudo cp --preserve=all "$config" "$backup"
    echo "Backup: $backup"
fi

temporary_dir=$(mktemp -d)
trap 'rm -rf "$temporary_dir"' EXIT

awk '!/^COMMANDS_(BEFORE|AFTER)_SAVE=/' "$config" \
    > "$temporary_dir/limine-snapper-sync.conf"
sudo install -o root -g root -m 0644 \
    "$temporary_dir/limine-snapper-sync.conf" "$config"

echo "Migração concluída; MAX_SNAPSHOT_ENTRIES foi preservado."
