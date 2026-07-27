#!/usr/bin/env bash
# Instala em /etc os arquivos de sistema versionados neste repo. Linux only.
#
# Por que um script e não o chezmoi: gerenciar arquivo fora do $HOME é um
# non-goal declarado do chezmoi. O destDir dele é sempre o home, então a
# árvore etc/ do source mapeia para ~/etc/... . O `--destination /` corrige
# isso para etc/, mas aí todo o resto do repo passa a mirar a raiz do sistema
# (dot_zshrc -> /.zshrc), o que é bem pior. Ver docs/openvpn.md.
#
# Rodar como você mesmo, NÃO com sudo — o script chama sudo só onde precisa.
# Renderizar template e descriptografar usam os seus dados e a sua chave age;
# com sudo o chezmoi olharia para o home do root e não acharia nenhum dos dois.
#
#   ./scripts/install-etc.sh              instala
#   ./scripts/install-etc.sh --dry-run    só mostra o que faria
#
# Idempotente: pode rodar de novo sem estragar nada.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY=1

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
skip() { printf '  \033[33mpulado\033[0m  %s\n' "$*"; }

# ── Pré-requisitos ───────────────────────────────────────────────
[[ "$(uname -s)" == "Linux" ]] || { echo "Linux only."; exit 1; }

if [[ $(id -u) -eq 0 ]]; then
  echo "Não rode com sudo. Rode como você mesmo — o script eleva sozinho onde"
  echo "precisa. Com sudo, o chezmoi não acha seus dados nem a chave age."
  exit 1
fi

command -v chezmoi >/dev/null || {
  echo "chezmoi não encontrado (pacman -S chezmoi)."
  echo "É ele que renderiza o template do dns-up e descriptografa o client.conf."
  exit 1
}

TMP="$(mktemp -d)"
chmod 700 "$TMP"
trap 'rm -rf "$TMP"' EXIT

# root:network se o grupo existir (Arch); senão root:root.
OWNER="root:root"
getent group network >/dev/null && OWNER="root:network"

# install_etc <arquivo-de-origem-já-pronto> <destino> <modo> <dono>
install_etc() {
  local src="$1" dst="$2" mode="$3" owner="$4"
  if [[ $DRY -eq 1 ]]; then
    printf '  sudo install -D -o %-4s -g %-8s -m %s  ->  %s\n' \
           "${owner%%:*}" "${owner##*:}" "$mode" "$dst"
    return 0
  fi
  sudo install -D -o "${owner%%:*}" -g "${owner##*:}" -m "$mode" "$src" "$dst"
  printf '  ok  %s  (%s %s)\n' "$dst" "$mode" "$owner"
}

say "Instalando arquivos de sistema a partir de $REPO"
[[ $DRY -eq 1 ]] && echo "(dry-run — nada será escrito)"

# ── Brave: Memory Saver balanceado ──────────────────────────────
# Políticas do Chromium valem para todos os user-data-dir do Brave. Teams e
# Outlook ficam fora do descarte para preservar chamadas e notificações.
if command -v brave >/dev/null; then
  install_etc "$REPO/etc/brave/policies/managed/memory-saver.json" \
              /etc/brave/policies/managed/memory-saver.json 644 root:root
else
  skip "/etc/brave/policies/managed/memory-saver.json — Brave não instalado"
fi

# ── DNS over TLS ─────────────────────────────────────────────────
# Só onde o systemd-resolved é quem resolve de fato. No WSL quem gera o
# /etc/resolv.conf é o próprio WSL, então o arquivo ficaria inerte e só
# confundiria na próxima vez que alguém for depurar DNS ali.
if [[ "$(systemctl is-enabled systemd-resolved 2>/dev/null)" == "enabled" ]] \
   && ! grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  install_etc "$REPO/etc/systemd/resolved.conf.d/dot.conf" \
              /etc/systemd/resolved.conf.d/dot.conf 644 root:root
  if [[ $DRY -eq 1 ]]; then
    printf '  systemctl restart systemd-resolved\n'
  else
    sudo systemctl restart systemd-resolved
  fi
else
  skip "/etc/systemd/resolved.conf.d/dot.conf — systemd-resolved não é o resolver aqui"
fi

# ── polkit: deixa o usuário openvpn falar com o systemd-resolved ──
install_etc "$REPO/etc/polkit-1/rules.d/49-openvpn-resolved.rules" \
            /etc/polkit-1/rules.d/49-openvpn-resolved.rules 644 root:root

# ── Scripts up/down do OpenVPN ───────────────────────────────────
# dns-up é template: os domínios de split DNS vêm do .chezmoidata.toml local.
chezmoi execute-template < "$REPO/etc/openvpn/scripts/executable_dns-up.sh.tmpl" \
        > "$TMP/dns-up.sh"
install_etc "$TMP/dns-up.sh" /etc/openvpn/scripts/dns-up.sh 755 root:root
install_etc "$REPO/etc/openvpn/scripts/executable_dns-down.sh" \
            /etc/openvpn/scripts/dns-down.sh 755 root:root

# ── Config do cliente OpenVPN (age) ──────────────────────────────
# Sem a identity não dá para descriptografar. Isso não é erro fatal: o resto
# dos arquivos é útil sozinho, e numa máquina nova a chave chega depois.
AGE_KEY="${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/age.txt"
if [[ -f "$AGE_KEY" ]]; then
  chezmoi decrypt "$REPO/etc/openvpn/client/encrypted_client.conf.age" \
          > "$TMP/client.conf"
  install_etc "$TMP/client.conf" /etc/openvpn/client/client.conf 640 "$OWNER"
  # O diretório precisa ser atravessável pelo processo do OpenVPN.
  if [[ $DRY -eq 1 ]]; then
    printf '  chmod 750 + chown %s  ->  /etc/openvpn/client\n' "$OWNER"
  else
    sudo chmod 750 /etc/openvpn/client
    sudo chown "$OWNER" /etc/openvpn/client
  fi
else
  skip "/etc/openvpn/client/client.conf — sem $AGE_KEY nesta máquina"
fi

# ── wsl.conf ─────────────────────────────────────────────────────
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
  install_etc "$REPO/etc/wsl.conf" /etc/wsl.conf 644 root:root
  echo "  (rode 'wsl.exe --shutdown' no Windows para valer)"
else
  skip "/etc/wsl.conf — esta máquina não é WSL"
fi

say "Pronto."
if [[ $DRY -eq 0 ]]; then
  echo "OpenVPN: sudo systemctl restart openvpn-client@client"
fi
