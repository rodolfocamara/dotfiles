#!/usr/bin/env bash
# Importa uma VPN OpenVPN no NetworkManager e aplica o endurecimento:
# split-tunnel, split-DNS e sem anúncio de nome na rede remota. Linux only.
#
# Por que existe: no Arch/KDE a VPN roda pelo NetworkManager (plasma-nm), não
# pelo openvpn-client@ do systemd que o etc/ deste repo configura. Reimportar
# um .ovpn cru dá um perfil que sequestra a rota default e o DNS inteiro — o
# que derruba o resto da internet. Este script deixa o perfil do jeito certo.
#
# NADA de específico da empresa mora aqui. Endpoints, sub-redes e domínios
# ficam no .chezmoidata.toml (por máquina, fora do git) e no próprio .ovpn,
# que também não vai pro repo. Este repositório é público.
#
#   ./scripts/setup-vpn-nm.sh --dry-run          mostra o que faria
#   ./scripts/setup-vpn-nm.sh                    usa workVpn.ovpnFile
#   ./scripts/setup-vpn-nm.sh ~/caminho/x.ovpn   usa esse arquivo
#
# Espera no .chezmoidata.toml (tudo opcional menos o ovpnFile ou o argumento):
#
#   [workVpn]
#   ovpnFile        = "~/Documents/vpn/EMPRESA.ovpn"
#   splitDnsDomains = ["empresa.com.br", "empresa.local"]
#   username        = "seu.usuario"
#
# Idempotente: rodar de novo só reaplica as configurações.

set -euo pipefail

DRY=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && { DRY=1; shift; }

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
skip() { printf '  \033[33mpulado\033[0m  %s\n' "$*"; }

# O KCM de rede do KDE mantém uma cópia inteira do perfil em memória. Se ele
# já estava aberto, aplicar essa cópia depois do script restaura silenciosamente
# never-default=no e quebra o split-tunnel de novo.
if pgrep -f '[s]ystemsettings.*kcm_networkmanagement' >/dev/null 2>&1; then
  if [[ $DRY -eq 1 ]]; then
    printf '  \033[33maviso\033[0m  feche Configurações do Sistema > Rede antes de aplicar\n'
  else
    cat >&2 <<'EOF'
Configurações do Sistema > Rede está aberto.
Feche a janela sem clicar em Aplicar e rode este script novamente; o editor
aberto pode sobrescrever o split-tunnel com uma cópia antiga do perfil.
EOF
    exit 1
  fi
fi

command -v nmcli >/dev/null || { echo "nmcli não encontrado."; exit 1; }
command -v chezmoi >/dev/null || { echo "chezmoi não encontrado (é ele que lê o .chezmoidata.toml)."; exit 1; }

# ── Dados locais ─────────────────────────────────────────────────
data() { chezmoi execute-template "$1" 2>/dev/null || true; }

OVPN="${1:-$(data '{{ (index (index . "workVpn" | default dict) "ovpnFile") | default "" }}')}"
OVPN="${OVPN/#\~/$HOME}"
# shellcheck disable=SC2016 # $w belongs to the chezmoi template, not Bash.
DOMAINS="$(data '{{- $w := (index . "workVpn") | default dict -}}
{{- range $i, $v := ((index $w "splitDnsDomains") | default list) }}{{ if $i }},{{ end }}~{{ $v }}{{ end }}')"
USERNAME="$(data '{{ (index (index . "workVpn" | default dict) "username") | default "" }}')"

[[ -n "$OVPN" ]] || {
  echo "Sem .ovpn: passe o caminho como argumento ou defina workVpn.ovpnFile no .chezmoidata.toml."
  exit 1
}
[[ -f "$OVPN" ]] || { echo "Não achei $OVPN"; exit 1; }

NAME="$(basename "$OVPN" .ovpn)"

say "Perfil: $NAME  (de $OVPN)"
[[ $DRY -eq 1 ]] && echo "(dry-run — nada será alterado)"

run() {
  if [[ $DRY -eq 1 ]]; then printf '  %s\n' "$*"; else "$@" >/dev/null; fi
}

# ── Importar (só se ainda não existir) ───────────────────────────
if nmcli -g NAME connection show 2>/dev/null | grep -qx "$NAME"; then
  echo "  perfil já existe — só reaplicando as configurações"
else
  run nmcli connection import type openvpn file "$OVPN"
fi

# ── Endurecimento ────────────────────────────────────────────────
# never-default: a VPN não vira rota default. Sem isso, TODO o tráfego sai
# pela rede da empresa — inclusive o que não é da empresa.
run nmcli connection modify "$NAME" ipv4.never-default yes ipv6.never-default yes

# split-DNS: só os domínios listados vão pro DNS da VPN. Sem isso, o resolver
# deles vê cada domínio que você consulta — seu histórico de navegação inteiro.
# O "~" marca domínio de roteamento (não vira sufixo de busca).
# dns-priority positivo impede o link de virar rota default de DNS.
if [[ -n "$DOMAINS" ]]; then
  run nmcli connection modify "$NAME" \
      ipv4.dns-search "$DOMAINS" ipv6.dns-search "$DOMAINS" \
      ipv4.dns-priority 50 ipv6.dns-priority 50
else
  skip "split-DNS — defina workVpn.splitDnsDomains no .chezmoidata.toml"
fi

# Não anunciar o nome da máquina dentro da rede remota. O DoT global é
# estrito, mas o DNS privado da VPN só atende DNS comum; desligá-lo neste link
# não afeta o Quad9 nem envia domínios públicos para o DNS da empresa.
run nmcli connection modify "$NAME" \
    connection.mdns 0 connection.llmnr 0 connection.dns-over-tls 0

# Usuário (a senha você digita no diálogo — nunca fica em arquivo).
if [[ -n "$USERNAME" ]]; then
  run nmcli connection modify "$NAME" vpn.user-name "$USERNAME"
else
  skip "vpn.user-name — defina workVpn.username, ou preencha no plasma-nm"
fi

say "Pronto."
if [[ $DRY -eq 0 ]]; then
  cat <<EOF
Conecte e, no diálogo da senha, marque "armazenar para todos os usuários"
(troca password-flags de 1/KWallet para 0/sistema — é o que permite subir
sem sessão gráfica aberta):

  nmcli connection up "$NAME"

Depois confira que a divisão está valendo:

  ip route get 1.1.1.1              # tem que sair pela sua interface normal
  resolvectl status tun0            # Default Route: no
  resolvectl query --cache=no <dominio-interno>   # tem que responder por tun0
EOF
fi
