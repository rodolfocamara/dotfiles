#!/usr/bin/env bash
# Cria /etc/openvpn/client/auth.txt com usuário e senha (uma vez).
# Rodar: sudo ./scripts/setup-openvpn-auth.sh
# Não versionar auth.txt — só existe em /etc na máquina.

set -e
AUTH_FILE="/etc/openvpn/client/auth.txt"
DIR="/etc/openvpn/client"

if [[ ! -d "$DIR" ]]; then
  echo "Crie primeiro o client.conf (ex.: sudo chezmoi apply -S /caminho/para/dotfiles)."
  exit 1
fi

if [[ -f "$AUTH_FILE" ]]; then
  read -p "auth.txt já existe. Sobrescrever? (s/N) " r
  [[ "${r,,}" != "s" && "${r,,}" != "y" ]] && exit 0
fi

echo "OpenVPN: credenciais para auth-user-pass (não ficam no Git)."
read -p "Usuário: " u
read -sp "Senha: " p
echo

printf '%s\n%s\n' "$u" "$p" > "$AUTH_FILE"
chmod 600 "$AUTH_FILE"
chown root:root "$AUTH_FILE"
echo "Criado: $AUTH_FILE (600, root:root)."

if ! grep -q "auth-user-pass" /etc/openvpn/client/client.conf 2>/dev/null; then
  echo "Adicione no client.conf:"
  echo "  CHEZMOI_DESTINATION_DIR=/ chezmoi edit /etc/openvpn/client/client.conf"
  echo "  (coloque a linha: auth-user-pass /etc/openvpn/client/auth.txt)"
  echo "Depois: sudo chezmoi apply -S $(cd -P "$(dirname "$0")/.." && pwd)  e  sudo systemctl restart openvpn-client@client"
else
  echo "Reinicie a VPN: sudo systemctl restart openvpn-client@client"
fi
