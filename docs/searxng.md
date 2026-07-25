# SearxNG local + MCP

Busca própria pros agentes, rodando em container rootless. Motivação: o
WebSearch embutido do Claude é US-only e enviesa tudo pra fonte americana.
Com SearxNG dá pra fixar `pt-BR` e ter fonte nacional em pesquisa de mercado,
regulatório, LGPD e fornecedor. Sem quota, sem custo por query, e a query não
sai pra terceiro — o que importa quando a própria pesquisa revela roadmap.

Um MCP serve todos os agentes: Claude Code, Claude Desktop, Codex, OpenCode,
Zed via ACP.

## Arquivos

```
dot_config/containers/systemd/searxng.container  --> ~/.config/containers/systemd/
dot_config/searxng/settings.yml                  --> ~/.config/searxng/
scripts/setup-searxng.sh                            roda uma vez, é idempotente
```

Fora do git, gerado na máquina: `~/.config/searxng/secret.env` (600).

## Instalar

```bash
~/Repos/dotfiles/scripts/setup-searxng.sh
```

O script confere podman, instala os dois arquivos de config (copiando do repo
se o `chezmoi apply` ainda não os colocou — não exige chezmoi instalado), liga
linger, gera o segredo, sobe o serviço, espera a API responder e registra o
MCP em `claude-personal` e `claude-work`. Rodar de novo é seguro.

Verificação rápida:

```bash
curl -s 'http://127.0.0.1:8888/search?q=teste&format=json' | head -c 200
```

## Os três atritos conhecidos

**1. `formats: [html, json]` tem que estar explícito.** O default é só `html` e
a API devolve 403. É o erro nº1 de quem monta isso.

**2. `limiter: true` derruba agente em minutos** (5 req/s, 60 req/min). O bind
é `127.0.0.1` e o único cliente é você — desligado. É isso que torna o Valkey
dispensável: sem limiter, o SearxNG não usa Redis pra nada.

**3. Engine quebra.** Ver abaixo — e é pior do que a fama sugere.

## Um quarto atrito, esse não documentado

O entrypoint da imagem faz `chown -R` em `/etc/searxng`. Se você montar o
**diretório** `~/.config/searxng`, ele chowna a tua config pra subuid (100976),
teu usuário perde a escrita e o `chezmoi apply` seguinte falha com
`Permission denied`.

O quadlet monta o **arquivo**, read-only:

```ini
Volume=%h/.config/searxng/settings.yml:/etc/searxng/settings.yml:ro
```

Se você já caiu nessa, o conserto é desfazer o chown de dentro do namespace
(no userns rootless, o uid 1000 do host é o 0 lá dentro):

```bash
systemctl --user stop searxng
podman unshare chown -R 0:0 ~/.config/searxng
```

## Engines: medido, não suposto

### Como medir sem se enganar

`engines=<nome>` **é ignorado em silêncio quando o nome não existe** — o
SearxNG roda o conjunto default e devolve resultado normal. Uma engine morta
parece viva, e uma engine inexistente parece ótima. Foi exatamente assim que a
primeira medição deste setup saiu errada.

A conferência é olhar o campo `engines` de cada resultado: se aparecer alguma
engine além da que você pediu, o filtro não pegou.

```bash
e='google cse'
curl -s "http://127.0.0.1:8888/search?q=teste&format=json&engines=$(python3 -c 'import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))' "$e")" \
| python3 -c '
import json,sys; d=json.load(sys.stdin)
print("n =", len(d["results"]))
print("engines vistas =", sorted({x for r in d["results"] for x in r.get("engines",[])}))
print("unresponsive =", d.get("unresponsive_engines"))'
```

Nomes reais saem de `curl -s http://127.0.0.1:8888/config`.

### Resultado (isolamento conferido)

| Engine           | Resultados | Situação                             |
|------------------|-----------:|--------------------------------------|
| `google cse`     |         20 | ok                                   |
| `duckduckgo`     |         10 | ok                                   |
| `bing`           |         10 | ok                                   |
| `duckduckgo web` |         10 | ok, mas desligada upstream — reserva |
| `mwmbl`          |          1 | vivo, irrelevante                    |
| `brave`          |          0 | HTTP 429 mesmo isolada e descansada  |
| `startpage`      |          0 | CAPTCHA                              |
| `qwant`          |          0 | CAPTCHA                              |
| `mojeek`         |          0 | sem erro, não devolve nada           |

Duas coisas contrariam o conselho comum de "DuckDuckGo + Brave + Startpage
primários, Google como reserva":

1. Brave, Startpage, Qwant e Mojeek estão **todos** inúteis deste IP. Seguir
   aquele conselho deixaria a busca dependendo só do DuckDuckGo.
2. **Não existe engine `google`** nesta versão — a busca web do Google é a
   `google cse`. `- name: google` no `settings.yml` não dá erro, só não faz
   nada. É a pegadinha silenciosa dessa configuração.

Sobram três engines gerais funcionando, e as três ficam ligadas de propósito:
se uma pegar captcha sob uso agressivo, a busca degrada em vez de morrer.
`duckduckgo web` fica declarada e desligada como quarta reserva já testada.

Reavaliar a cada 2-3 meses. Se uma engine sumir dos resultados:

```bash
journalctl --user -u searxng -n 50 | grep -iE 'error|denied|captcha'
```

## Outros agentes

O MCP é o mesmo binário e o mesmo endpoint; muda só onde se declara.

**Codex** — `~/.codex/config.toml`:

```toml
[mcp_servers.searxng]
command = "npx"
args = ["-y", "mcp-searxng"]
env = { SEARXNG_URL = "http://127.0.0.1:8888" }
```

**OpenCode** — `~/.config/opencode/opencode.json`:

```json
{
  "mcp": {
    "searxng": {
      "type": "local",
      "command": ["npx", "-y", "mcp-searxng"],
      "environment": { "SEARXNG_URL": "http://127.0.0.1:8888" },
      "enabled": true
    }
  }
}
```

**Zed** — `settings.json`, em `context_servers`:

```json
{
  "context_servers": {
    "searxng": {
      "source": "custom",
      "command": "npx",
      "args": ["-y", "mcp-searxng"],
      "env": { "SEARXNG_URL": "http://127.0.0.1:8888" }
    }
  }
}
```

**Claude Desktop** — `~/.config/Claude/claude_desktop_config.json`, mesma forma
em `mcpServers`.

Ferramentas expostas pelo `mcp-searxng` (v1.11.1): `searxng_web_search`,
`searxng_search_suggestions`, `searxng_instance_info` e `web_url_read` — esse
último busca URL e converte pra markdown, o que contorna sites que respondem
403 pro fetch do agente.

## Valkey, se um dia fizer falta

Não está instalado. Só passa a valer a pena se você ligar o `limiter` (por
expor o SearxNG além do loopback) ou quiser cache de resultado. Nesse caso,
`~/.config/containers/systemd/valkey.container`:

```ini
[Unit]
Description=Valkey para o SearxNG

[Container]
ContainerName=valkey
Image=docker.io/valkey/valkey:alpine
Network=searxng.network
Volume=valkey-data.volume:/data
Exec=valkey-server --save 30 1 --loglevel warning

[Service]
Restart=always

[Install]
WantedBy=default.target
```

Aí é preciso também criar `searxng.network` e `valkey-data.volume` (quadlets
`.network` e `.volume`), trocar o `PublishPort` do searxng por `Network=`, e
apontar `valkeydb.url: redis://valkey:6379/0` no `settings.yml`.

## Operação

```bash
systemctl --user status searxng      # estado
systemctl --user restart searxng     # depois de editar settings.yml
journalctl --user -u searxng -f      # logs
podman auto-update                   # atualiza a imagem (AutoUpdate=registry)
```

Depois de mexer no `settings.yml` pelo repo: `chezmoi apply` e então
`systemctl --user restart searxng` — o arquivo é montado, não copiado, mas o
SearxNG só lê no boot.
