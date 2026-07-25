#!/usr/bin/env bash
# SearxNG local + MCP para os agentes. Linux only.
# Rodar depois do `chezmoi apply`: ./scripts/setup-searxng.sh
#
# Idempotente: pode rodar de novo sem estragar nada. O segredo é gerado uma
# vez e nunca sobrescrito (regerar invalida as sessões abertas do SearxNG).

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF_DIR="$HOME/.config/searxng"
QUADLET_DIR="$HOME/.config/containers/systemd"
SECRET_FILE="$CONF_DIR/secret.env"
UNIT="searxng.service"
URL="http://127.0.0.1:8888"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

# ── Pré-requisitos ───────────────────────────────────────────────
command -v podman >/dev/null || { echo "podman não encontrado (pacman -S podman)"; exit 1; }

# Normalmente quem instala esses dois é o `chezmoi apply`. Mas nem toda
# máquina tem chezmoi, e o setup não depende dele — se faltar, copia do repo.
install_from_repo() {
  local src="$REPO/$1" dst="$2"
  [[ -f "$dst" ]] && return 0
  [[ -f "$src" ]] || { echo "Não achei $src"; exit 1; }
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  echo "Instalado: $dst"
}

install_from_repo dot_config/searxng/settings.yml "$CONF_DIR/settings.yml"
install_from_repo dot_config/containers/systemd/searxng.container "$QUADLET_DIR/searxng.container"

# Sem linger o serviço morre quando a sessão fecha.
if [[ "$(loginctl show-user "$USER" --property=Linger --value 2>/dev/null)" != "yes" ]]; then
  say "Habilitando linger (serviço sobe sem sessão aberta)"
  loginctl enable-linger "$USER"
fi

# ── Segredo (fora do git) ────────────────────────────────────────
if [[ -f "$SECRET_FILE" ]]; then
  echo "secret.env já existe — mantido."
else
  say "Gerando $SECRET_FILE"
  printf 'SEARXNG_SECRET=%s\n' "$(openssl rand -hex 32)" > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
fi

# ── Serviço ──────────────────────────────────────────────────────
say "Subindo $UNIT"
systemctl --user daemon-reload
# Nada de `enable`: em quadlet o [Install] é resolvido pelo gerador, que já
# cria o link em default.target.wants/. `enable` falha em unit gerada.
systemctl --user restart "$UNIT"

printf 'Aguardando a API responder'
for _ in $(seq 1 60); do
  if curl -fsS "$URL/search?q=ping&format=json" >/dev/null 2>&1; then
    printf ' ok\n'; break
  fi
  printf '.'; sleep 2
done

if ! curl -fsS "$URL/search?q=ping&format=json" >/dev/null 2>&1; then
  echo
  echo "A API JSON não respondeu. Diagnóstico:"
  echo "  systemctl --user status $UNIT"
  echo "  journalctl --user -u $UNIT -n 50"
  echo "Se der 403, confira 'formats: [html, json]' em settings.yml."
  exit 1
fi

# ── MCP nos dois perfis do Claude ────────────────────────────────
register_mcp() {
  local profile="$1" dir="$HOME/.$1"
  if ! command -v claude >/dev/null; then
    echo "claude não está no PATH — pulei o registro do MCP em $profile."
    return
  fi
  mkdir -p "$dir"
  if CLAUDE_CONFIG_DIR="$dir" claude mcp get searxng >/dev/null 2>&1; then
    echo "MCP searxng já registrado em $profile."
    return
  fi
  say "Registrando MCP searxng em $profile"
  CLAUDE_CONFIG_DIR="$dir" claude mcp add -s user searxng \
    -e "SEARXNG_URL=$URL" \
    -- npx -y mcp-searxng
}

register_mcp claude-personal
register_mcp claude-work

say "Pronto."
echo "  Web UI:  $URL"
echo "  Status:  systemctl --user status $UNIT"
echo "  Logs:    journalctl --user -u $UNIT -f"
echo "  Teste:   curl -s '$URL/search?q=teste&format=json' | head -c 200"
