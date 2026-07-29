# Arquivo dos pull requests

Registro dos PRs de 2025-05 a 2026-07, preservado quando o repositório foi
apagado e recriado. Apagar era a única forma de descartar commits órfãos que
o GitHub continuava servindo por SHA depois de uma reescrita de histórico —
e apagar leva os PRs junto.

As descrições valem mais que o diff: elas dizem *por que*. Os links para
github.com estão mortos de propósito; a numeração é a do repositório antigo.

---

## #1 — Add local SearxNG + MCP for agent web search (Linux)

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `780375113`

Branch: `claude/searxng-mcp-podman-setup-ef7b0c` → `main` · 7 arquivos

Replaces the US-biased built-in WebSearch with a local metasearch instance pinned to `pt-BR`, reachable by every agent (Claude Code, Codex, OpenCode, Zed) through one MCP server. No quota, no per-query cost, and queries never leave the machine — which matters when the research itself reveals roadmap.

## What lands

| File | Purpose |
|---|---|
| `dot_config/containers/systemd/searxng.container` | Rootless quadlet, bound to `127.0.0.1:8888` |
| `dot_config/searxng/settings.yml` | Engine + format + limiter config |
| `scripts/setup-searxng.sh` | Idempotent installer, registers the MCP |
| `docs/searxng.md` | Setup, engine measurement method, snippets for other agents |

Quadlet rather than compose: it is systemd-native, so it survives reboot without `podman generate` and the desired state stays versioned. Verified wired into `default.target.wants`, with linger already on.

Valkey is deliberately **not** included. With `limiter: false` SearxNG does not use Redis for anything; the quadlet for it is documented in `docs/searxng.md` if the limiter is ever turned on.

## The three known frictions

1. `formats: [html, json]` must be explicit — the default is `html` only and the API 403s.
2. `limiter: true` kills an agent in minutes (5 req/s). Bind is loopback and the only client is the owner, so it is off — and that is what makes Valkey unnecessary.
3. Engines break. See below; it was worse than expected.

## Two things found by testing rather than assuming

**Mounting the config directory breaks the next `chezmoi apply`.** The image entrypoint runs `chown -R` on `/etc/searxng`. With the directory mounted it chowns `~/.config/searxng` to a subuid (100976), the user loses write access to their own config, and the following apply fails with `Permission denied`. Reproduced here. The quadlet mounts the *file*, read-only:

```ini
Volume=%h/.config/searxng/settings.yml:/etc/searxng/settings.yml:ro
```

**The engine advice was inverted, and the first measurement of it was wrong.** Two chained findings:

- `engines=<name>` is **silently ignored** when the name does not exist — SearxNG runs the default set and returns normal-looking results, so a dead engine looks alive. The first per-engine probe here measured the default set eight times over.
- There is **no engine named `google`** in this version; Google web search is `google cse`. `- name: google` in `settings.yml` raises no error and simply does nothing.

Re-measured with isolation verified via each result's `engines` field:

| Engine | Results | Status |
|---|---:|---|
| `google cse` | 20 | ok |
| `duckduckgo` | 10 | ok |
| `bing` | 10 | ok |
| `duckduckgo web` | 10 | ok, disabled upstream — kept as reserve |
| `brave` | 0 | HTTP 429 even isolated and rested |
| `startpage` | 0 | CAPTCHA |
| `qwant` | 0 | CAPTCHA |
| `mojeek` | 0 | no error, returns nothing |

Brave, Startpage, Qwant and Mojeek are all useless from this IP, so the common "DuckDuckGo + Brave + Startpage primary, Google reserve" setup would leave search depending on DuckDuckGo alone. The three that work are all enabled on purpose: if one hits a captcha under aggressive use, search degrades instead of dying.

## Verified end to end

- Service `active (running)`, wired into `default.target.wants` for boot.
- Config ownership stays `rcamara:rcamara` across restarts.
- Final query: 38 results, **34 of them `.br`**, zero unresponsive engines.
- MCP `✔ Connected` in both `claude-personal` and `claude-work`; `searxng_web_search` and `web_url_read` both exercised — the latter fetched `openai.com` as markdown without the 403.
- `setup-searxng.sh` run three times, including from a fully clean state.

## Notes

`chezmoi` is not installed on this Linux box, so `setup-searxng.sh` falls back to copying the two config files from the repo and does not require it.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #2 — feat: track Zed config in chezmoi with a VSCode-like profile

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `d3e3ee3b3`

Branch: `feat/zed-vscode-profile` → `main` · 9 arquivos

Zed era o único editor fora do chezmoi. Este PR coloca ele lá e alinha com o VSCode, para trocar de editor parar de custar músculo.

## Estrutura

Conteúdo único em `.chezmoitemplates/zed/`, incluído por quatro wrappers de uma linha — o Zed lê `%APPDATA%\Zed\` no Windows e `~/.config/zed/` no Linux/macOS. `.chezmoiignore` corta a árvore errada em cada OS.

```
.chezmoitemplates/zed/settings.json     <- fonte da verdade
.chezmoitemplates/zed/keymap.json
dot_config/zed/*.tmpl                   --> ~/.config/zed/          (Linux/macOS)
AppData/Roaming/Zed/*.tmpl              --> %APPDATA%\Zed\          (Windows)
```

## O que descobri antes de escrever

**O keymap default do Zed no Linux já é praticamente o do VSCode.** Já vêm de fábrica: `ctrl-p`, `ctrl-shift-p`, `ctrl-t`, `ctrl-b`, `ctrl-alt-b`, `ctrl-j`, ``ctrl-` ``, `ctrl-shift-e/f/g/x/m/o`, `ctrl-w`, `ctrl-k w`, `alt-1..9`, `ctrl-tab`, `f2`, `f8`, `f12`, `ctrl-.`, `ctrl-h`, `ctrl-r`, `alt-up/down`, `ctrl-shift-k`, `ctrl-/`, `ctrl-d`, `ctrl-shift-l`, `ctrl-\`, e os acordes `ctrl-k`.

Sobrou **uma** divergência real, que é o que o `keymap.json` corrige: o Zed inverte copiar-linha com inserir-cursor.

| | Zed | VSCode (e este PR) |
|---|---|---|
| `shift-alt-up/down` | inserir cursor | duplicar linha |
| `ctrl-alt-up/down` | — | inserir cursor |

O binding é escopado em `Editor && mode == full` para não roubar o `ctrl-alt-up/down` do scroll do painel de agente (contexto `AcpThread`).

## Settings

Cada chave foi conferida contra o `assets/settings/default.json` do Zed upstream; só entrou o que **diverge** do default. Uma primeira versão tinha ~20 chaves idênticas ao default, todas removidas.

| Área | Default do Zed | Aqui |
|---|---|---|
| `base_keymap` | `"Zed"` | `"VSCode"` |
| Explorer / Outline / Git | dock à direita | à esquerda |
| Painel de agente | dock à esquerda | à direita, 560px |
| Minimap | desligado | `"auto"` |
| Abas | sem ícone, sem cor de git | ícone + git status + marca erro |
| Barra de menu | escondida | visível no título |
| `format_on_save` | `"off"` | `"on"` |
| Fonte do agente | 12px | 14px |

O "jeitão Claude Desktop" do painel já é default no Zed 1.12 (largura de leitura centralizada, threads na lateral, Enter envia) — só dock, largura e fonte precisaram mudar.

## Verificação

- `chezmoi cat` renderiza os dois alvos (Linux e Windows) idênticos
- `chezmoi apply ~/.config/zed` aplicado nesta máquina, `chezmoi status` limpo
- `chezmoi ignored` confirma `AppData` cortado fora do Windows
- JSONC dos dois arquivos validado por parser

## Nota

Os alvos são wrappers, então **`chezmoi re-add` não funciona** neles — editar `.chezmoitemplates/zed/` e aplicar. Está documentado em `docs/zed.md` e no README.

Este PR toca `.chezmoiignore`, assim como os outros dois PRs em aberto — conflito de merge é possível, mas em regiões diferentes do arquivo.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #3 — feat: gate targets by machine profile, not just by OS

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `40d763e9d`

Branch: `feat/chezmoi-machine-profile` → `main` · 3 arquivos

O chezmoi separa alvos por SO. Só que SO não é a granularidade que este repo precisa: as duas máquinas Linux rodam desktops diferentes — uma Hyprland, outra KDE Plasma. O `dot_config/hypr`, `waybar` e `wofi` são corretos numa e lixo na outra.

## Por que isso importa

Não falha alto, que é justamente o problema. Na máquina KDE:

```
antes:   47 alvos pendentes (A)  <- 20 deles são config de Hyprland que nunca vai ser aplicada
depois:  23 alvos pendentes (A)  <- todos reais
```

Ruído desse tamanho faz o `chezmoi status` deixar de ser lido — e aí um alvo pendente de verdade some no meio.

Verificado nesta máquina: `plasmashell` e `kwin_wayland` instalados, `Hyprland`, `waybar`, `wofi` e `kitty` não; `~/.config/hypr`, `~/.config/waybar`, `~/.config/wofi` e `~/.config/kitty` não existem.

## Como funciona

Perfil vem do `.chezmoidata.toml` na raiz do source — por máquina, gitignored. É o mecanismo que o repo **já referenciava** no `chezmoi.toml.tmpl` (para `sourceDirOverride`) e nunca tinha usado:

```toml
profile = "hyprland"   # ou "kde", "generic"
```

Sem o arquivo, detecta pelo binário do compositor, então uma máquina Hyprland nova recebe o stack sem nenhum setup:

```
{{ $profile := (index . "profile") | default (ternary "hyprland" "generic" (ne (lookPath "Hyprland") "")) }}
```

## O que o gate corta

| Alvo | Regra |
|---|---|
| `.config/hypr/`, `.config/waybar/`, `.config/wofi/`, `.config/kitty/` | só no perfil `hyprland` |
| `.wslconfig` | só no Windows — quem lê é o host, em `%USERPROFILE%\.wslconfig` |
| `etc/wsl.conf` | só dentro do WSL |

As quatro linhas de desktop saíram do bloco `{{ if eq .chezmoi.os "windows" }}`: o gate de `$profile` resolve para `generic` no Windows também, então estavam duplicando a mesma decisão em dois lugares.

## Verificação

Os três caminhos foram testados com `chezmoi execute-template` + `chezmoi ignored`:

| `.chezmoidata.toml` | perfil | alvos de desktop ignorados |
|---|---|---|
| ausente | `generic` (detectado) | 4 |
| `profile = "kde"` | `kde` | 4 |
| `profile = "hyprland"` | `hyprland` | 0 (stack aplicado) |

## Fora de escopo, mas achado no caminho

**Os alvos de `/etc` estão mapeando errado.** `chezmoi target-path etc/wsl.conf` retorna `/home/rcamara/etc/wsl.conf` — ou seja, um `chezmoi apply` de usuário criaria uma árvore `~/etc/openvpn/...` no home. Os blocos `[ "etc/..." ] target = ...` do `chezmoi.toml.tmpl` não estão surtindo efeito (o próprio comentário no arquivo diz que chezmoi v2 não suporta esse formato). Isso responde por 9 dos 23 pendentes que sobraram. **Não mexi aqui** — é um bug de outra natureza e merece PR próprio.

Este PR toca `.chezmoiignore`, assim como os outros dois em aberto — conflito de merge é possível, mas em regiões diferentes do arquivo.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #4 — feat: track fish config in chezmoi (cma abbr + portability guards)

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `e819da1b8`

Branch: `claude/affectionate-mclaren-46b84b` → `main` · 5 arquivos

O README documenta `cma` como o fluxo diário, mas ele nunca existiu no shell que a máquina realmente usa. fish é o shell de login no Arch/CachyOS e não estava no source:

```
$ type cma
type: Could not find 'cma'
```

Só `dot_zshrc` e `dot_bashrc` eram rastreados.

## Achado antes de mexer

`dot_config/fish/functions/` **já existia** no source dir, com `claude-personal.fish` e `claude-work.fish` — mas **untracked no git desde 28/abr**. O chezmoi já aplicava essas funções nesta máquina, enquanto um clone novo do repo as perderia sem avisar. Agora estão versionadas.

## O que entra e o que não entra

| Item | Decisão |
|---|---|
| `config.fish` | versionar — era o buraco real |
| `functions/*.fish` | versionar — existiam no source, faltava o `git add` |
| `conf.d/` | vazio, nada a versionar |
| `completions/` | vazio e regenerado de man pages → não |
| `fish_variables` | store de universal vars, `0600`, reescrito a cada `set -U` → não |

`completions/` e `fish_variables` entraram no `.chezmoiignore` não como no-op, mas como guarda: `chezmoi add` passa a pular esses caminhos.

## Abbrs: só o delta real

Antes de escolher, li o `/usr/share/cachyos-fish-config/cachyos-config.fish`. A distro **já define** `ls`, `ll`, `la`, `lt`, `..`, `...` e `grep --color` — duplicar só criaria conflito. O que o fish não tinha vindo do `dot_zshrc`:

- `cma` → `chezmoi apply`
- `gs ga gc gp gb gd gco gl`
- `c` → `clear`, `repos` → `cd ~/Repos`

Fora de propósito: `cdi` (zoxide **não está instalado** nesta máquina, apesar de estar na tabela de stack do README), `grep=rg` (brigaria com o `grep --color=auto` da distro), `tree` (o `lt` cobre) e `update-all` (é `apt`; em Arch a distro já traz `update` via pacman).

## Mudança de comportamento que vale revisar

Como o repo também mira WSL, blindei o `config.fish` em vez de versionar verbatim: o `source` do config da CachyOS virou condicional, `starship`/`mise`/`direnv` ficaram atrás de `command -q`, e `set -gx SHELL /usr/bin/fish` virou `(status fish-path)`. Nesta máquina o resultado é idêntico; num WSL sem esses pacotes, a versão verbatim cuspiria erro em toda sessão.

## Verificação

`chezmoi diff` mostrou só o `config.fish` — as duas functions já batiam byte a byte com `$HOME`. Apliquei **escopado em `~/.config/fish`**, de propósito: um `chezmoi apply` seco também reescreveria `.bashrc`, `.zshrc`, `.gitconfig` e `.claude-personal/settings.json`, que hoje divergem do target e são outro assunto.

```
$ fish -l -i -c 'abbr --query cma gs gl; and echo ALL ABBRS PRESENT'
ALL ABBRS PRESENT

$ chezmoi status | grep fish
(vazio — source == $HOME)

$ chezmoi ignored | grep fish
(vazio no Linux — correto)
```

`fish_variables` (0600) e os dirs vazios seguem intocados: não há prefixo `exact_`, então o chezmoi não remove o que não gerencia.

## Ordem de merge

Este PR é o último da fila. Testei o merge nas duas ordens possíveis, não só na que me convém:

| cenário | resultado |
|---|---|
| #3 → este | **clean** |
| #2 → este | conflito: `README.md`, 1 linha |
| este direto no main | **clean** |

Posicionei a entrada do `.chezmoiignore` de propósito longe da região que o #3 reescreve (o #3 tira `hypr/waybar/wofi/kitty` do bloco `{{ if eq .chezmoi.os "windows" }}` e reescreve o comentário acima dele), e abri mão de um ajuste cosmético nesse comentário para não colidir. Por isso o `.chezmoiignore` fecha clean contra os dois PRs.

Sobrou um conflito de **uma linha** no `README.md`, na lista do Layout, porque o #2 edita a mesma linha. A resolução é a união:

```
dot_config/     --> ~/.config/   fish, starship, hypr, waybar, kitty, zed, searxng, quadlets
```

## Fora de escopo, mas achado no caminho

**Os PRs #2 e #3 conflitam entre si**, independente deste. Ambos adicionam linhas no bloco `{{ if ne .chezmoi.os "windows" }}` do `.chezmoiignore` (`.wslconfig` + `etc/wsl.conf` no #3, `AppData/` no #2) e o merge quebra nas duas ordens. Quem for o segundo resolve — é união simples, mas melhor saber antes.

**A identidade git gerenciada não está aplicada.** O `~/.gitconfig` vivo perdeu o bloco `[user]` (e `[push]`, `[url]`, `[core]`): ferramentas de credencial — `gh` e `git-credential-manager` — sobrescreveram o arquivo gerenciado, deixando só blocos `[credential]`. É o que responde pelo ` M .gitconfig` no `chezmoi status`. Commitei passando a identidade do próprio source via `git -c`, sem tocar em config, porque um `chezmoi apply ~/.gitconfig` restauraria o `[user]` **derrubando os helpers de credencial** que hoje autenticam o push. Precisa de decisão real (provavelmente unir os dois lados no template), não de um apply.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #5 — fix: take /etc out of chezmoi and install it with a script

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `0aa86b6c7`

Branch: `fix/etc-targets-out-of-chezmoi` → `main` · 7 arquivos

A árvore `etc/` nunca chegou em `/etc`. O `destDir` do chezmoi é sempre o `$HOME`:

```
$ chezmoi target-path etc/openvpn/scripts/executable_dns-up.sh.tmpl
/home/rcamara/etc/openvpn/scripts/dns-up.sh          # não /etc/...
$ chezmoi target-path etc/wsl.conf
/home/rcamara/etc/wsl.conf
```

Ou seja: um `chezmoi apply` de usuário criaria uma árvore lixo `~/etc/openvpn/...` no home, e os arquivos nunca chegariam no destino. Isso respondia por 10 dos 47 alvos pendentes nesta máquina.

## Os três mecanismos documentados eram todos no-op

Testei um por um:

| Documentado em | Comando | O que acontecia de verdade |
|---|---|---|
| `docs/openvpn.md` | `CHEZMOI_DESTINATION_DIR=/ chezmoi edit ...` | essa variável não existe no chezmoi — ignorada em silêncio (`CHEZMOI_DEST_DIR` também não funciona) |
| `README.md`, `docs/openvpn.md` | `sudo chezmoi apply -S ~/Repos/dotfiles` | com sudo o `$HOME` vira `/root`, então o destino vira `/root/etc/...` e o sourceDir vira `/root/.local/share/chezmoi` |
| `.chezmoi.toml`, `chezmoi.toml.tmpl` | blocos `[ "etc/..." ] target = "/etc/..."` | formato não suportado no chezmoi v2 — o comentário dentro do próprio `chezmoi.toml.tmpl` já admitia isso |

## Por que não usar `--destination /`

Ele **funciona** para `etc/`. O problema é o resto:

```
$ chezmoi --destination / target-path dot_zshrc
//.zshrc
$ chezmoi --destination / target-path dot_config/starship.toml
//.config/starship.toml
```

Um `sudo chezmoi apply --destination /` sem argumentos de path espalharia seus dotfiles na raiz do sistema. Não vale o risco por quatro arquivos — e gerenciar arquivo fora do `$HOME` é um [non-goal declarado](https://github.com/twpayne/chezmoi/discussions/1510) do projeto.

## A correção

`etc/` passa a ser ignorado em todo OS, e `scripts/install-etc.sh` instala:

```
$ ./scripts/install-etc.sh --dry-run
  sudo install -D -o root -g root  -m 644  ->  /etc/polkit-1/rules.d/49-openvpn-resolved.rules
  sudo install -D -o root -g root  -m 755  ->  /etc/openvpn/scripts/dns-up.sh
  sudo install -D -o root -g root  -m 755  ->  /etc/openvpn/scripts/dns-down.sh
  pulado  /etc/openvpn/client/client.conf — sem /home/rcamara/.config/chezmoi/age.txt nesta máquina
  pulado  /etc/wsl.conf — esta máquina não é WSL
```

Roda **como você**, não com sudo: renderizar o template do `dns-up` e descriptografar o `client.conf` precisam do seu `.chezmoidata.toml` e da sua chave age. O `sudo` entra só nos `install`. Idempotente, com `--dry-run`, e pula o `client.conf` com mensagem clara quando a chave age não existe (que é o caso desta máquina).

## Dois arquivos removidos

Ambos existiam só para servir o fluxo quebrado:

- **`run_after_openvpn_client_permissions.sh`** — só agia como root, durante o `sudo chezmoi apply` que nunca funcionou. A lógica de `chmod 750` / `chown root:network` foi para dentro do script.
- **`.chezmoi.toml` da raiz do source** — o chezmoi **nunca leu esse arquivo**. O `chezmoi init` só procura `.chezmoi.$FORMAT.tmpl`. Provado com `chezmoi dump-config`: o arquivo declara um `recipient` do age, e o config efetivo tem `recipient: ""`.

## ⚠️ Um ponto que precisa dos seus olhos

O `recipient` do age que estava naquele arquivo morto foi para o `chezmoi.toml.tmpl`, **ainda comentado**, com o comando de verificação junto. Não liguei sozinho: se aquele valor estiver desatualizado, descomentar faria o `chezmoi add --encrypt` criptografar para uma chave que você não tem mais. Confira antes:

```bash
age-keygen -y < ~/.config/chezmoi/age.txt
```

Se bater com `age1qgz7c54kk...`, é só descomentar — e aí o `chezmoi add --encrypt` volta a funcionar (hoje não funciona, o recipient está vazio).

## Verificação

- `chezmoi managed | grep etc` → vazio; nenhum alvo aponta mais para `~/etc`
- alvos pendentes: **47 → 37** (os 10 fantasmas de `etc/`)
- `chezmoi ignored` renderiza sem erro
- `bash -n` no script e no `dns-up.sh` renderizado
- sem referências órfãs aos dois arquivos removidos

Nada foi escrito em `/etc` — só dry-run, como pedido.

Este PR toca `.chezmoiignore`, assim como os PRs #2 e #3.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #6 — fix: reconcile .gitconfig drift without breaking push auth

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `91cbc39d4`

Branch: `claude/wonderful-dewdney-4e4971` → `main` · 2 arquivos

## Problema

O `~/.gitconfig` gerenciado havia derivado: continha **apenas** blocos de credencial escritos por `gh auth setup-git` e `git-credential-manager configure`, e nada do conteúdo do próprio template. Consequência: `git config --get user.email` retornava vazio e commits falhavam com *"Author identity unknown"*.

A armadilha é que `chezmoi apply ~/.gitconfig` restaurava `[user]` mas **apagava os helpers que autenticam `git push`**.

## O que a investigação revelou

Os blocos do `gh` no arquivo live eram **config morta**. O git acumula todo `credential.helper` correspondente na ordem do arquivo, e um `helper =` vazio *reseta a lista coletada até ali*. O reset genérico em `[credential]` — escrito por último, pelo GCM — vinha **depois** dos blocos do github e os descartava silenciosamente. `GIT_TRACE` no config live confirmou: só `git-credential-manager get` era invocado.

Ou seja, o trabalho do `gh auth setup-git` já estava sendo anulado pelo GCM antes desta mudança.

Validei a semântica com três layouts de teste antes de desenhar a solução:

| Layout | Ordem | Helpers invocados |
|---|---|---|
| A | reset genérico **depois** dos per-host (= arquivo live) | GCM apenas |
| B | reset genérico **antes**, per-host aditivo | GCM → gh (fallback) |
| C | reset genérico antes, per-host **com reset próprio** | gh apenas |

## Decisão: manter no template, não em include separado

Um include fora do controle do chezmoi **não resolve a deriva**, porque `gh` e o GCM escrevem via `git config --global` — isto é, dentro do próprio `~/.gitconfig`, não no que ele inclui. Mover os blocos deixaria exatamente o mesmo arquivo derivando na próxima vez que qualquer uma das ferramentas rodasse.

Mantendo o chezmoi como dono, `live == renderizado`, e tanto `chezmoi apply` quanto as ferramentas externas convergem. Também segue o precedente do repo (`dot_gitconfig-work.tmpl` já embutia config de GCM em template).

## Mudanças

**`dot_gitconfig.tmpl`**
- **Removido `helper = cache`** — conflitava diretamente com o helper que o git realmente usava e é estritamente mais fraco (plaintext em memória vs. secretservice).
- **Reset genérico primeiro, blocos per-host depois** e *aditivos* (sem reset próprio) — Layout B. O GCM continua primário, preservando exatamente o que autentica hoje, e o `gh` passa a ser fallback real em vez de linhas mortas.
- **Caminhos detectados com `lookPath`** em vez de hardcoded, com cada bloco condicionado à ferramenta estar instalada. `credentialStore = secretservice` só no Linux; no Windows usa o nome curto `manager`, evitando caminho absoluto com espaços e barras invertidas.

**`dot_gitconfig-work.tmpl`** — mesmo bug em forma pior: o reset estava *no meio da lista*, deixando `/usr/local/bin/git-credential-manager` como helper efetivo — caminho que não existe nesta máquina (`/usr/bin`). Como alvo de `includeIf`, ele carrega **depois** do `~/.gitconfig`, então qualquer declaração de helper ali ou apaga ou duplica a principal. Agora carrega só o que é específico de work (`[user]`, `azreposCredentialType`, `useHttpPath`) e herda o helper. O gate de OS virou gate de ferramenta — Azure DevOps não é específico de Linux, o caminho quebrado era.

## Verificação

- `git config --get user.email` resolve; commit real sai com o autor correto
- `git push` autentica — **o push deste branch é a prova de ponta a ponta**
- `gh auth status` segue logado
- `chezmoi diff` nos dois alvos vazio e `chezmoi status` sem linha de `.gitconfig` — a linha `M .gitconfig` sumiu
- Fallback do `gh` exercitado trocando o GCM por um helper que não retorna nada: o git tenta, não obtém nada, e o `gh` fornece credencial válida
- Degradação testada com `PATH` stubado: sem `gh`/GCM o arquivo renderiza sem nenhuma seção `[credential]`, em vez de apontar para binários inexistentes

## Pontos de atenção

1. `[url "https://github.com/"] insteadOf = git@github.com:` estava no template mas não no arquivo live, então passa a ficar **ativo**: remotes SSH em outros repos serão reescritos para HTTPS e passarão por estes helpers em vez das chaves SSH. É a intenção pré-existente do template, não algo introduzido aqui, mas vale saber que entra em efeito.
2. `gnome-keyring` está inativo e `~/.local/share/keyrings` não existe, ainda assim o GCM devolve credenciais sem interação — não identifiquei o que satisfaz o `secretservice`. Mantive como está porque funciona comprovadamente, e o template documenta as alternativas (`gpg`/pass, `cache`, `plaintext`) se parar de funcionar.

Não toquei em `.chezmoiignore` nem `README.md`, para não colidir com os PRs #2, #3 e #4.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #7 — fix: keep npm-global PATH and CachyOS zsh config across an apply

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `e7f4e4815`

Branch: `fix/preserve-live-shell-settings` → `main` · 2 arquivos

Antes do primeiro apply de verdade nesta máquina, o `chezmoi diff` mostrou dois ajustes que só existiam nos arquivos vivos e seriam descartados em silêncio:

| Arquivo | Linha que só existe no vivo |
|---|---|
| `~/.bashrc` | `export PATH="$HOME/.npm-global/bin:$PATH"` |
| `~/.zshrc` | `export PATH="$HOME/.npm-global/bin:$PATH"` |
| `~/.zshrc` | `source /usr/share/cachyos-zsh-config/cachyos-config.zsh` |

O npm desta máquina tem o prefix no `$HOME`, então sem essa entrada nada instalado com `npm i -g` resolve. Adicionado nos dois, com guarda no diretório para virar no-op onde não existe.

O config do CachyOS é o setup da distro — o equivalente em zsh do que o `dot_config/fish/config.fish` já faz. Mesma guarda e mesma posição: primeiro, para o resto poder sobrescrever.

## Verificação

`bash -n` no `dot_bashrc` passa. `zsh -n` não roda aqui (zsh não está instalado nesta máquina — o `.zshrc` do repo é para o WSL); a sintaxe usada é POSIX simples.

Comparando linha a linha o arquivo vivo com o que o repo escreveria, o que sobra é só diferença intencional:

- `[[ $- != *i* ]] && return` → o repo usa a forma `case $- in *i*)`, equivalente
- `PS1='[\u@\h \W]\$ '` → substituído de propósito pelo starship
- `npm-global` → agora presente, na forma com guarda

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #8 — feat: reproducible NetworkManager VPN profile, split-tunnel by default

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `40f75da58`

Branch: `feat/vpn-networkmanager-setup` → `main` · 2 arquivos

A máquina Arch/KDE roda a VPN pelo **NetworkManager**, não pelo `openvpn-client@` do systemd que a árvore `etc/` configura. Nada no repo capturava isso, então o perfil estava montado à mão — e um import cru de `.ovpn` deixa o perfil sequestrando a rota default e o DNS inteiro.

Consequência prática, observada: ao conectar, **o resto da internet parava de funcionar** (tudo saía pelo gateway da empresa) e o resolver deles passava a ver cada domínio consultado — ou seja, o histórico de navegação inteiro.

## O que o script fixa

`scripts/setup-vpn-nm.sh` importa o `.ovpn` se preciso e crava os quatro ajustes que importam:

| Ajuste | Por quê |
|---|---|
| `ipv4/ipv6.never-default yes` | a VPN não vira rota default; só as sub-redes empurradas passam por ela |
| `ipv4/ipv6.dns-search ~dominio` | só esses domínios vão pro DNS da VPN (`~` = domínio de roteamento) |
| `ipv4/ipv6.dns-priority 50` | positivo, então o link nunca vira rota default de DNS |
| `connection.mdns 0` / `llmnr 0` | para de anunciar o nome da máquina dentro da rede remota |

Idempotente (detecta perfil existente e só reaplica) e com `--dry-run`.

## Nada da empresa no repo

**Este repositório é público.** Exportar o perfil publicaria os gateways, os DNS internos, o domínio interno e as **27 sub-redes** que o servidor empurra — reconhecimento pronto pra quem quiser atacar a rede.

Então segue o mesmo padrão que o commit `8b61c23` ("Move work VPN domain to local data") já tinha estabelecido: endpoint, domínios e usuário no `.chezmoidata.toml` (gitignored), `.ovpn` fora do repo.

```toml
[workVpn]
ovpnFile        = "~/Documents/vpn/EMPRESA.ovpn"
splitDnsDomains = ["empresa.com.br", "empresa.local"]
username        = "seu.usuario"
```

Conferi antes de commitar que o diff não contém nenhuma referência à empresa (nome, IPs, hostnames, sub-redes).

## Verificação

Os ajustes foram aplicados nesta máquina e validados com o túnel no ar:

| Consulta | Link que respondeu |
|---|---|
| domínio interno | `tun0` |
| `claude.ai` | `wlan0` |

| Destino | Sai por |
|---|---|
| internet (1.1.1.1) | `wlan0` — default intacta |
| sub-rede interna | `tun0` |
| LAN de casa | `wlan0` |

`resolvectl status tun0` mostra `Default Route: no` e `-LLMNR -mDNS`. O `--dry-run` do script reproduz exatamente esses mesmos comandos.

## Doc

`docs/openvpn.md` agora começa dizendo **qual dos dois caminhos** se aplica — seguir o do systemd num desktop é trabalho jogado fora.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #9 — fix: fall back to a real codex when nvm is absent

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `83836c1df`

Branch: `fix/codex-wrapper-without-nvm` → `main` · 1 arquivos

Regressão causada pelo primeiro `chezmoi apply` de verdade nesta máquina.

O wrapper fixa o codex numa versão de node gerenciada pelo nvm e aborta com `exit 127` quando `~/.nvm` não existe. Isso era inofensivo enquanto ele só rodava na máquina WSL. Ao aplicar o repo no Arch, ele foi instalado em `~/.local/bin` — que tem precedência no PATH — e passou a **sombrear o codex que funcionava**, instalado via `npm -g` com prefix no `$HOME`:

```
~  > codex --yolo
codex wrapper: NVM not found at /home/rcamara/.nvm
```

Ou seja: numa máquina onde o codex estava instalado e funcionando, o wrapper o tornou inacessível.

## Correção

Antes de desistir, procura outro `codex` no PATH que não seja o próprio wrapper (compara o caminho resolvido com `readlink -f`) e faz `exec` nele. Só falha quando realmente não há nada para rodar — e aí a mensagem diz isso.

## Verificação

```
$ codex --version
codex-cli 0.145.0
```

`bash -n` passa. Na máquina WSL, onde `~/.nvm` existe, o caminho antigo continua idêntico — o fallback só entra no `if` que já abortava.

---

## #10 — feat: DNS over TLS so the ISP stops seeing every domain

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `4ab26456a`

Branch: `feat/dns-over-tls` → `main` · 2 arquivos

Olhar o roteador tornou a lacuna concreta: a rede é **duplo NAT** (o WAN do Xiaomi é `192.168.15.72`, atrás do roteador do provedor) e o DNS dele está em "automático". Então toda consulta saía desta máquina em texto puro e era legível em **três saltos** antes de chegar a um resolver:

```
PC → Xiaomi (192.168.31.1) → roteador do provedor (192.168.15.1) → resolver do provedor
```

Isso não é metadado solto: é o histórico de navegação.

## Escolhas, e por quê

| Linha | Motivo |
|---|---|
| `DNS=9.9.9.9#dns.quad9.net` | Quad9 — fundação suíça sem fins lucrativos. O `#nome` valida o certificado: sem ele o canal é cifrado mas não autenticado |
| `FallbackDNS=` (vazio) | o systemd traz uma lista embutida que ele usa **em texto puro** quando o DNS= falha — seria um furo silencioso exatamente no que isto quer fechar |
| `DNSOverTLS=yes` | modo estrito: falha em vez de cair pro plaintext |
| `DNSSEC=allow-downgrade` | valida onde a zona suporta, sem quebrar as zonas mal configuradas que ainda existem |
| `Domains=~.` | rota padrão de DNS, preservando domínios mais específicos — **o split-DNS da VPN continua funcionando** |
| sem IPv6 | este provedor não entrega IPv6 (`IPv6连接类型: None`); só renderia timeout |

`DNSOverTLS=yes` quebra portal cativo de wifi público. O arquivo documenta o opt-out temporário de uma linha em vez de escolher `opportunistic` caladamente.

## Verificado antes de escrever

```
9.9.9.9:853         OK
149.112.112.112:853 OK
subject=C=CH, ST=Zurich, O=Quad9, CN=dns.quad9.net
Verification: OK
```

Ou seja: o provedor nem bloqueia nem intercepta DoT aqui.

## Instalação

`install-etc.sh` instala só onde o systemd-resolved é quem resolve de fato — **não no WSL**, onde o próprio WSL escreve o `resolv.conf` e o arquivo ficaria inerte, enganando quem for depurar DNS depois.

```
$ ./scripts/install-etc.sh --dry-run
  sudo install -D -o root -g root  -m 644  ->  /etc/systemd/resolved.conf.d/dot.conf
  systemctl restart systemd-resolved
  ...
```

## Falta um passo fora do repo

O arquivo sozinho não basta: o `wlan0` recebe `192.168.31.1` via DHCP e vira **rota padrão de DNS** no resolved, então os servidores globais nunca seriam consultados. Depois de instalar, é preciso:

```bash
nmcli connection modify Hogsmeade ipv4.ignore-auto-dns yes
nmcli connection up Hogsmeade
```

Efeito colateral honesto: nomes locais servidos pelo roteador deixam de resolver (o `.local` via mDNS continua).

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #11 — docs: network runbooks for the failure modes we just built in

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `4812ee58c`

Branch: `docs/network-runbooks` → `main` · 2 arquivos

Quatro coisas mudaram em como esta máquina fala com a rede: **DNS over TLS estrito**, **DNS do roteador ignorado**, **MAC de wifi estável por rede** e **VPN split-tunnel**. Cada uma compra privacidade e cada uma tem um modo de falha que não vai ser óbvio depois.

Formato: **sintoma → por quê → comando**. Escrito para quem esbarrar nisso daqui a seis meses sem lembrar do raciocínio.

## Os runbooks

| Sintoma | O que a pessoa provavelmente vai culpar | O que é de verdade |
|---|---|---|
| wifi público não abre a página de login | "a rede está ruim" | DoT estrito não deixa o portal sequestrar o DNS |
| VPN conectou e a internet parou | a VPN | o perfil reassumiu a rota default |
| `AUTH_FAILED` | senha da chave privada | senha **da conta** — se o TLS passou, a da chave está certa |
| perfil da VPN parou do nada | plugin/pacote | `vpn.data` esvaziou; reimportar |
| `.local` parou | DNS | **não é DNS** — é mDNS/avahi, via nsswitch |
| consulta lenta em rede nova | DoT | tentativa falha contra o DNS local antes de cair no Quad9 |

Mais: reverter o MAC, conferir se o split-DNS da VPN ainda vale, VPN que não sobe no boot, e o wrapper do codex.

## Duas entradas existem porque a resposta é contra-intuitiva

- **`.local` nunca toca o DNS.** O `nsswitch.conf` põe `mdns_minimal` antes, com `[NOTFOUND=return]`. Verificado: `resolvectl query <host>.local` **falha** enquanto `avahi-resolve` responde. Quem for depurar isso olhando resolver vai perder tempo.
- **Reserva de DHCP tem que ser feita para o MAC em uso**, não o de fábrica — senão nasce morta. Foi exatamente a armadilha que quase pegou a gente ao ligar a randomização.

## Nada identificável no arquivo

Peguei isso na revisão do próprio diff, prestes a commitar: o rascunho tinha o **SSID da casa** (geolocalizável via WiGLE), o **nome do empregador** no perfil da VPN, o nome de um dispositivo e o IP do roteador — num repositório **público**. Mesma linha que o PR #8 traçou ao não exportar o perfil da VPN.

Os comandos agora leem os nomes do `nmcli` para `$WIFI` e `$VPN` no topo do documento:

```bash
WIFI=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
VPN=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="vpn"{print $1; exit}')
```

Testado: descobre os dois corretamente.

## Verificação

Os comandos de leitura foram executados de verdade, não escritos de memória. Um estava errado no rascunho: `connection.secondaries` é lista de **UUID** e não aceita nome — corrigido para buscar o UUID via `nmcli -g connection.uuid`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #12 — fix(docs): the openvpn username lives in vpn.data, not vpn.user-name

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `371b63c0b`

Branch: `fix/runbook-vpn-username` → `main` · 1 arquivos

Erro no runbook que acabou de ser mergeado, pego ao conferir um perfil que **funciona**.

O runbook mandava checar e setar `connection.vpn.user-name`. O plugin openvpn do NetworkManager lê `username` de dentro do `vpn.data`. Num perfil que conecta normalmente:

```
$ nmcli -g vpn.user-name connection show "$VPN"
                                    <- vazio
$ nmcli connection show "$VPN" | grep '^vpn.data' | tr ',' '\n' | grep username
username = <preenchido>              <- é este que vale
```

Ou seja, o check documentado mandaria a pessoa perseguir um campo que é vazio por design, no meio de um `AUTH_FAILED` — exatamente quando ela está com menos paciência.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #13 — feat: fix and document the two NVIDIA black-screen failures

`MERGED` · @rodolfocamara · aberto 2026-07-25 · merged 2026-07-25 · `e81543901`

Branch: `claude/monitor-lg-nao-reconhecido-14b09c` → `main` · 5 arquivos

Started from "my top LG stopped working, Linux doesn't seem to see it." Linux did see it — and chasing that turned up a second, unrelated bug sitting next to it.

## 1. Hotplug modeset race

The display powers on, KDE reports it `connected` and `enabled` at the right mode, and the panel stays black. `nvidia_drm` takes the HPD, reads the EDID, builds the output, and never finishes link training. The journal shows the connector reasserting in bursts.

Cycling the mode forces a fresh modeset and the link comes up. That's `fix-monitor`:

```fish
fix-monitor              # every enabled external display
fix-monitor HDMI-A-1     # just that one
fix-monitor --dry-run    # print the commands only
```

It reads `kscreen-doctor --json`, so it works off mode ids rather than parsing ANSI-coloured text. The internal panel is skipped deliberately — the bug is on the external link, and `eDP` is where you'd read the error if the restore leg failed. If it does fail, the message prints the exact command to undo by hand.

## 2. Uncovered suspend path

Latent — it doesn't bite until you suspend with monitors attached.

`nvidia-utils` ships `NVreg_PreserveVideoMemoryAllocations=1`, but `nvidia-suspend.service` comes disabled, so nothing actually writes VRAM out before S3. The driver is told to preserve and nobody saves.

The packaged sleep hook does not close this. Outside the suspend-then-hibernate special case, `/usr/lib/systemd/system-sleep/nvidia` handles exactly one hook:

```sh
case "$1" in
    post)
        /usr/bin/nvidia-sleep.sh "resume"
        ;;
esac
```

Only `post`. There is no `pre` branch — resume is covered, suspend is not. Harmless under `s2idle`; this machine runs `deep`, where the VRAM genuinely goes away.

`scripts/setup-nvidia-sleep.sh` enables `nvidia-suspend` and `nvidia-resume`. It skips `nvidia-hibernate` when `systemd-hibernate` is masked — that unit's only `WantedBy` is the masked target, so enabling it would link to a hook that never fires. On a machine where hibernation is live, it includes the unit.

## Telling them apart

`docs/nvidia-displays.md` leads with the test that separates both from a bad cable. Two channels share the cable and mean different things:

| Channel | Powered by | Proves |
|---|---|---|
| EDID | +5V from the cable | cable and plug are fine — nothing more |
| DDC/CI | the monitor's scaler | the monitor is awake and processing signal |

EDID reads while DDC/CI is dead → driver bug. Both dead → hardware. The doc also flags LG's `Deep Sleep Mode`, which produces that same signature from the monitor side and is worth ruling out before touching a driver.

## Verified

```
fix-monitor --dry-run            DP-4 + HDMI-A-1 picked up, eDP-1 excluded, exit 0
fix-monitor --dry-run DP-99      clean error, exit 1
setup-nvidia-sleep.sh --dry-run  detected deep/S3, the hibernate mask,
                                 and PreserveVideoMemoryAllocations=1
fish -n / bash -n                clean
```

Not verified here: the live mode cycle (needs eyes on the panels) and `systemctl enable` (sudo prompts for a password). Both are on me to call out rather than imply.

`jq` and `ddcutil` were installed but absent from the curated package list; added, since the function and the diagnosis depend on them.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #14 — fix: recover display and bluetooth mouse after wake

`MERGED` · @rodolfocamara · aberto 2026-07-26 · merged 2026-07-26 · `158008daa`

Branch: `agent/recover-display-bluetooth-after-wake` → `main` · 10 arquivos

## Summary

- add a KDE user service that watches screen unlock and real resume events, waits for the graphics stack to settle, and forces a fresh modeset on the affected NVIDIA output
- add safe MX Master 3S recovery that tries a normal Bluetooth connection first, then power-cycles the controller only when BlueZ is stuck, while preserving bonds and reconnecting previously active devices
- extend `fix-monitor` with `--top`, scope the new targets to the KDE chezmoi profile, and document both manual and automatic recovery
- make `setup-nvidia-sleep.sh` report that NVIDIA sleep units remain dormant while `systemd-suspend.service` is masked

## Root cause

The observed wake is normally Plasma locking the session and powering displays off after 30 minutes, not an S3 suspend. The external NVIDIA output remains connected and enabled in KScreen, but the display link fails to train until a new modeset is forced.

The Bluetooth bond for the MX Master 3S remains valid (`Paired`, `Bonded`, and `Trusted`), but BlueZ can become stuck in discovery and a direct connection hangs. Power-cycling the controller restores the HID connection without re-pairing.

## Impact

After unlock or resume, the service automatically repairs `HDMI-A-1` and verifies the Bluetooth mouse connection. It never removes or recreates the mouse bond, so a recoverable controller failure does not become a manual Easy-Switch pairing flow.

## Validation

- `bash -n` on all changed Bash scripts
- `fish -n` on `fix-monitor.fish`
- `shellcheck` on all changed Bash scripts
- `systemd-analyze --user verify` on the deployed unit
- clean `git diff --check` and `chezmoi status`
- `fix-monitor --top --dry-run` selected `HDMI-A-1` and preserved its original 2560x1080@144 mode
- synthetic screen-unlock D-Bus event triggered the modeset and completed successfully in the user journal
- live Bluetooth recovery restored the MX Master 3S without re-pairing; the mouse is connected with its existing bond and the previously connected FreeBuds were restored

---

## #15 — feat: pacotes por perfil de máquina, não uma lista só

`MERGED` · @rodolfocamara · aberto 2026-07-26 · merged 2026-07-26 · `afb1f1384`

Branch: `claude/linux-updates-46507e` → `main` · 7 arquivos

## O problema

O `.chezmoiignore` já corta `.config/hypr/`, `waybar/`, `wofi/` e `kitty/` fora do
perfil `hyprland` — foi o que o `40d763e` resolveu. O `packages/pacman.txt` ficou de
fora dessa decisão: lista única, sem perfil.

Resultado prático na máquina KDE: `bootstrap-arch.sh` instala Hyprland, hyprpaper,
hyprlock, hypridle, xdg-desktop-portal-hyprland, waybar, wofi, kitty, grim e slurp —
um compositor inteiro que nunca vai subir, e cujos configs o chezmoi se recusa a
aplicar ali. As duas metades do repo discordavam sobre o que é uma máquina KDE.

## O que muda

`pacman.txt` vira a base (vale em qualquer Arch) e o que é de um desktop só vai para
`pacman.<profile>.txt`. Só `hyprland` tem arquivo hoje; um `pacman.kde.txt` passa a
valer sozinho no dia que existir, sem tocar no script.

O perfil resolve na mesma ordem do template, para as duas metades não voltarem a
divergir: `DOTFILES_PROFILE` no ambiente → `.chezmoidata.toml` → binário do Hyprland
no PATH.

## Antes / depois

Nesta máquina (`profile = "kde"`), via `bootstrap-arch.sh`:

```
antes:   34 pacotes  (10 deles o stack do Hyprland)
depois:  24 pacotes
```

O `--dry-run` novo torna isso verificável sem instalar nada, inclusive para a outra
máquina:

```
$ ./scripts/install-packages.linux-arch.sh --dry-run
Profile: kde
  + packages/pacman.txt
--- would install (24 packages) ---

$ DOTFILES_PROFILE=hyprland ./scripts/install-packages.linux-arch.sh --dry-run
Profile: hyprland
  + packages/pacman.txt
  + packages/pacman.hyprland.txt
--- would install (34 packages) ---
```

## Dois achados no caminho

**`install-packages.linux-arch.sh` não rodava.** Lia `${CHEZMOI_SOURCE_DIR}` sob
`set -u`, mas `scripts/` é ignorado pelo chezmoi — a variável nunca está setada, e o
script morria justamente quando executado na mão, que é o único jeito de executá-lo:

```
$ ./scripts/install-packages.linux-arch.sh
./scripts/install-packages.linux-arch.sh: line 10: CHEZMOI_SOURCE_DIR: unbound variable
```

Agora resolve o repo pelo próprio caminho, mantendo a variável como override.

**`bootstrap-arch.sh` reimplementava a leitura da lista.** Mexer só no outro script
inverteria o bug: máquina Hyprland nova sairia *sem* Hyprland. Passou a delegar, e a
resolução de perfil existe em um lugar só.

## Fora de escopo, de propósito

Não removi o suporte a Hyprland do repo. O `docs/machine-profiles.md` documenta duas
máquinas Linux ativas, uma delas Hyprland — o gate serve as duas.

`zsh`, `zsh-autosuggestions`, `zoxide` e `chezmoi` seguem na base mesmo não estando
instalados na máquina KDE (o shell de login aqui é fish, e o `chezmoi` veio pelo
instalador, em `~/.local/bin`). É uma discussão separada da do desktop.

## Teste

- `bash -n` nos dois scripts
- `--dry-run` nos perfis `kde`, `hyprland` e `generic` (worktree sem `.chezmoidata.toml`)
- nenhuma referência pendente a `pacman.txt` fora das novas: `grep -rn` em `scripts/` e `docs/`

Nada foi instalado ou removido do sistema por este PR.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #16 — fix: prevent bluetooth discovery and reduce log noise

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `bb1b0e7b7`

Branch: `agent/cleanup-system-logs` → `main` · 12 arquivos

## What changed

- disable KDE Connect's Bluetooth transport on the KDE profile while keeping LAN enabled
- refresh Brave's local desktop override from the packaged file and preserve the `Meta+Y` shortcut
- remove unusable SearxNG engines and mount an explicit local bot-detection config
- add an idempotent Limine/Snapper migration from deprecated `COMMANDS_*` options to package-provided hooks
- document the workarounds and profile-specific behavior

## Why

KDE Connect 26.04 was repeatedly starting Bluetooth discovery, producing tens of thousands of warnings and contending with Bluetooth input/audio traffic. The same boot also exposed a malformed Brave desktop override, deprecated Limine/Snapper settings, and noisy SearxNG engine initialization.

## Impact

- KDE Connect continues to work over LAN; only its Bluetooth transport is disabled.
- The MX Master bond is preserved.
- Limine keeps `MAX_SNAPSHOT_ENTRIES=6`; the migration does not expand the boot menu.
- NTFS and Wi-Fi configuration are intentionally untouched.

## Validation

- `shellcheck` and `bash -n` pass for the new and changed scripts
- `chezmoi apply`, dry-run, and status complete cleanly
- KDE Connect reports `AsyncLinkProvider|disabled`
- BlueZ reports `Discovering: no`; the MX Master remains connected
- Brave's override passes `desktop-file-validate`
- SearxNG returns HTTP 200 and a live search returned 30 results
- removed SearxNG engines are absent from `/config`, with no new startup warnings
- no failed system or user units

---

## #17 — feat: track Brave work PWAs

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `8ec209eac`

Branch: `agent/brave-work-pwas` → `main` · 4 arquivos

## O que mudou

- adiciona launchers reproduzíveis para Teams, Outlook e Azure DevOps
- mantém os três aplicativos no perfil isolado `Brave-Browser-Work`
- limita os launchers ao perfil de máquina KDE no chezmoi

## Por quê

O cliente Teams para Linux usado antes era não oficial e não concluía o login. Os PWAs do Brave oferecem uma instalação mais confiável e mantêm a sessão de trabalho separada do perfil pessoal.

## Impacto

Após aplicar o chezmoi no perfil KDE, Teams, Outlook e Azure DevOps ficam disponíveis como aplicativos independentes usando o mesmo perfil Work do Brave.

## Validação

- templates renderizados com `chezmoi execute-template`
- launchers renderizados validados com `desktop-file-validate`
- `git diff --check`

---

## #18 — feat: persist KDE screenshot and brightness workflow

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `a9630d030`

Branch: `agent/kde-workflow-persistence` → `main` · 11 arquivos

## O que mudou

- registra `Meta+Shift+S` para capturar uma região, salvar o PNG e publicar imagem + caminho no clipboard
- compila o provedor Wayland multimídia usando o protocolo oficial de `wayland-protocols`
- registra `Ctrl+Alt+Up` para alternar os perfis lógicos de brilho 5/30/60
- aplica pesos por tela: monitor inferior 1x, superior 7/6x e notebook 2/3x
- restaura o brilho após login, desbloqueio e resume usando o serviço KDE já existente

## Por quê

O clipboard padrão atendia sites com a imagem, mas não permitia ao terminal escolher o caminho do arquivo. A solução anterior também dependia de um watcher e unidades adicionais. Para brilho, aplicar o mesmo percentual produzia luminância visual desigual e o PowerDevil sobrescrevia o monitor superior.

## Impacto

No perfil lógico 60, as telas ficam em 60% (inferior), 70% (superior) e 40% (notebook). O screenshot fica salvo automaticamente e cada aplicativo escolhe o formato adequado do mesmo clipboard.

## Validação

- `bash -n` e `shellcheck` nos scripts e templates renderizados
- launchers validados com `desktop-file-validate`
- provedor compilado com `wayland-scanner`, `cc` e `-Wall -Wextra -Wpedantic`
- unidade verificada com `systemd-analyze --user verify`
- calibração 60/70/40 confirmada após atraso e reinício do serviço
- `git diff --check`

---

## #19 — feat: keep KDE work desktop reproducible

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `f584cef3a`

Branch: `agent/reproducible-kde-desktop` → `main` · 7 arquivos

## Estado mantido

- ativa Memory Saver balanceado no Brave e preserva Teams/Outlook
- mantém launchers reproduzíveis de ChatGPT e Claude com seus perfis corretos
- torna o ajuste DDC de brilho tolerante a uma falha transitória
- integra tudo aos mecanismos atuais de instalação e atualização do repo

## Objetivo

Este PR registra apenas o estado desejado para reconstruir o ambiente em uma instalação nova. Não inclui backups, watchers antigos, scripts de migração nem artefatos da sessão em que a configuração foi criada.

## Validação

- `bash -n` e `shellcheck`
- JSON validado com `jq`
- templates renderizados pelo chezmoi
- launchers validados com `desktop-file-validate`
- política comparada com o arquivo aplicado em `/etc`
- `git diff --check`
- brilho confirmado em 60/70/40

---

## #20 — fix: split screenshot clipboard targets

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-28 · `bc6088880`

Branch: `agent/fix-screenshot-clipboard-targets` → `main` · 6 arquivos

## What changed

- let Spectacle publish `image/png` directly to the regular Wayland clipboard
- save that PNG to `Pictures/Screenshots`
- publish only the saved file path to the primary selection for terminal workflows
- remove the custom C/Wayland multi-MIME clipboard provider and its build hook
- add a one-time chezmoi migration that removes the obsolete provider files
- update the desktop entry and shortcut documentation

## Why

The previous provider advertised both `image/png` and `text/plain` on the same clipboard. Codex Desktop and Claude Desktop preferred the text representation, so pasting inserted the screenshot path instead of attaching the image.

Separating the representations preserves both workflows:

- regular paste in graphical apps attaches the PNG
- primary-selection paste in Kitty inserts the saved path

Using Spectacle's native `--copy-image` path also avoids the post-capture delay and removes the custom polling/provider complexity.

## Validation

- `bash -n` on the screenshot script and rendered chezmoi hooks
- rendered desktop entry passes `desktop-file-validate`
- mocked end-to-end script run verifies:
  - Spectacle is invoked with `--background --region --copy-image`
  - clipboard PNG is persisted
  - the saved path is sent only to the primary selection
- `git diff --check`

---

## #21 — feat: cap battery charge on the Legion without a DKMS toolkit

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `961ba0567`

Branch: `claude/linux-battery-management-74e7de` → `main` · 6 arquivos

## Contexto

Substituto no Linux para o toggle de "segurar a bateria em 80%" que existia num app Lenovo no Windows.

**O 80% não é reproduzível neste hardware.** Esse número vem de ThinkPad, que expõe `charge_control_start_threshold` / `charge_control_end_threshold` e aceita percentual arbitrário. Nesta Legion 5 15IAH7H nenhum desses nós existe — o EC oferece um liga/desliga (conservation mode) com teto definido pelo firmware, que a Lenovo documenta em ~55–60%. Não é ajustável por software.

## O que entra

| Arquivo | Papel |
|---|---|
| `etc/udev/rules.d/90-ideapad-conservation.rules` | reaplica `conservation_mode=1` em add/bind; passa o atributo para `root:wheel 0664` |
| `dot_local/bin/executable_battery-conservation` | `status` / `on` / `off` / `toggle`, sem sudo |
| `scripts/install-etc.sh` | bloco guardado — pula onde o atributo não existe |
| `.chezmoiignore` | helper no bloco do perfil `kde` |
| `docs/battery.md` | o porquê + alternativas descartadas |

Reaplicar no boot parece redundante (o EC costuma guardar o estado sozinho), mas um reset de BIOS devolve "carregar até 100% e segurar lá" em silêncio — que é exatamente a falha que isso previne. `off` valer só até o próximo boot é intencional.

## Por que nenhum pacote do AUR

- **`lenovo-legion-linux-toolkit-release`** (o mais popular na busca): instala um `modprobe.d` que faz blacklist de `ideapad_laptop`, `ideapad_acpi` e todos os `lenovo_wmi_*` — mata o driver de que isso depende — e lista `cuda` (~5 GB) como dependência dura. Um voto no AUR.
- **`lenovolegionlinux-dkms-git`** (johnfanv2): é a alternativa séria e não faz blacklist, mas o ganho exclusivo é curva de fan. Power modes já são nativos no kernel 7.1 via `lenovo_wmi_gamezone` (`platform_profile_choices` → `low-power balanced performance custom`). Não paga um módulo DKMS recompilando a cada kernel.
- **TLP**: thresholds só funcionam em ThinkPad/alguns Dell, e conflita com o `power-profiles-daemon` já instalado.

Registrado em `docs/battery.md` para a pesquisa não se repetir.

## Verificação

```
/sys/.../VPC2004:00/conservation_mode → root wheel 0664, valor 1
battery-conservation off  → charge_types: Fast [Standard] Long_Life
battery-conservation on   → charge_types: Fast Standard [Long_Life]
```

`udevadm verify` e `shellcheck -S warning` limpos; dry-run do installer mostra o bloco na ordem certa; helper deployado e rodando pelo PATH.

**Não verificado:** persistência num reboot real (só testado via `udevadm trigger`) e o valor exato do teto — a bateria está em 100%/Full na tomada, e o número real só aparece descarregando e replugando.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #22 — feat: run Wave as the terminal workspace

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-28 · `99ab8f048`

Branch: `agent/terminal-sidebar-workflow` → `main` · 8 arquivos

## Escopo

Reduzido pra **só o Wave**. A versão anterior deste PR carregava kitty, tmux e herdr junto; esses ficam de fora e seguem instalados na máquina como arquivos locais não versionados, pra serem removidos depois.

8 arquivos, todos com dependência direta no Wave.

## O que entra

**`codex-terminal-title`** — o Wave nomeia cada bloco da sidebar pelo shell em foco. O script empurra o nome do chat do Codex por cima enquanto um agente roda, e o hook de prompt do fish devolve o path quando termina.

Os dois saem de fininho fora do Wave: o hook checa `TERM_PROGRAM` e `WAVETERM`, e o helper precisa de `WAVETERM_JWT` e `WAVETERM_BLOCKID` pra falar com a API do bloco. Em kitty ou num terminal comum, nada acontece.

**`install-waveterm.sh`** — fixa a release e confere o digest publicado pelo GitHub antes de instalar, então download corrompido ou adulterado falha alto em vez de entrar.

**`python` e `sqlite`** no `pacman.txt` porque o `codex-terminal-title` lê o store de sessões do Codex através deles. `kitty` **não** entra — foi pro lado de fora junto com o resto.

## Verificação

- `shellcheck` limpo em `codex-terminal-title`, `install-waveterm.sh` e no template renderizado do `run_onchange_50`.
- `desktop-file-validate` OK no `waveterm.desktop`; `settings.json` parseia; `fish -n` valida o `config.fish`.
- `.chezmoiignore` renderiza, com apenas os três gates do Wave (`.config/waveterm/`, `waveterm.desktop`, `codex-terminal-title`).
- Conferido que nenhuma linha de kitty ou herdr vazou. A única ocorrência é um comentário dentro do próprio script explicando que OSC 2 é entendido por esses dois — texto, não dependência.

---

## #23 — fix: keep VPN split routing working

`CLOSED` · @rodolfocamara · aberto 2026-07-27

Branch: `agent/fix-vpn-split-routing` → `main` · 3 arquivos

## What changed

- refuse to modify the NetworkManager profile while KDE's network settings editor holds a stale in-memory copy
- disable DNS-over-TLS only on the private VPN link while keeping strict DoT on the public resolver
- document the expected `-DNSOverTLS`, split-DNS, and default-route diagnostics

## Why

Two independent conditions could make the VPN appear to break normal internet access again:

1. KDE System Settings could overwrite `never-default=yes` after the hardening script ran.
2. Private VPN resolvers do not accept strict DNS-over-TLS, so internal lookups failed even though the public resolver should remain protected.

The profile remains a split tunnel: it does not install a default route, and only explicitly configured internal domains use VPN DNS. No proxy is introduced.

## Privacy

The repository contains no company endpoint, domain, username, password, or `.ovpn` data. Machine-specific values remain in ignored chezmoi data and the external VPN profile.

## Validation

- `git diff --check`
- `bash -n scripts/setup-vpn-nm.sh`
- `shellcheck scripts/setup-vpn-nm.sh`
- live NetworkManager/resolved verification performed on the configured machine

> **Comentário de @rodolfocamara:** Fechando como duplicado: o conteúdo destes 3 arquivos entrou no main via #25, byte a byte idêntico ao que estava aqui. Verificado com `git show origin/agent/fix-vpn-split-routing:<arquivo> | diff - <arquivo>` nos três — sem diferença.

Nada se perdeu: `connection.dns-over-tls 0` no link da VPN e a guarda do KCM de rede do KDE estão no main desde 5beda78.

---

## #24 — fix: bridge Bitwarden desktop to the Brave extension

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `dc8ee25bd`

Branch: `claude/bitwarden-native-messaging-brave-e05f1f` → `main` · 3 arquivos

## Problema

A extensão do Bitwarden no Brave pedia a senha mestra toda vez, mesmo com o app desktop aberto e destravado ao lado. Não era conta, sincronização nem configuração da extensão.

O app desktop escreve o manifest de Native Messaging sozinho, mas só nos navegadores que ele conhece. No Linux, `getLinuxNMHS()` em `/usr/lib/bitwarden/app.asar` (versão 2026.3.1) retorna exatamente quatro:

```js
Firefox:          ~/.mozilla/
Chrome:           ~/.config/google-chrome/
Chromium:         ~/.config/chromium/
"Microsoft Edge": ~/.config/microsoft-edge/
```

Brave não está na lista, e navegador Chromium não lê o `NativeMessagingHosts/` de outro navegador. Então `connectNative("com.8bit.bitwarden")` falha. O diretório do Brave tinha só um `com.bitwarden.desktop.json` de abril — nome antigo do host, hoje usado apenas pela extensão do Firefox, que dava a impressão de estar configurado sem estar.

## Solução

`run_onchange_after_60-bridge-bitwarden-brave.sh.tmpl` copia para o diretório do Brave o manifest que o próprio Bitwarden escreveu (Chrome, Chromium ou Edge, o primeiro que existir), e remove o manifest legado.

Copiar em vez de versionar um JSON pronto é intencional: `path` aponta pro proxy do pacote (`/usr/lib/bitwarden/desktop_proxy` em instalação nativa, outro caminho em flatpak) e `allowed_origins` muda quando o Bitwarden publica novos IDs de extensão. Derivando da origem, os dois acompanham o upgrade sozinhos. O hash no topo do script é o do manifest de origem, então update do Bitwarden dispara o script de novo.

Isso precisa viver no chezmoi porque **cada update do Bitwarden reescreve os manifests do Chrome e Chromium e continua ignorando o Brave**.

Gate por `.chezmoi.os == "linux"` (não por perfil de máquina — Brave é o navegador principal nas duas). Sai limpo em máquina sem Brave e em máquina onde o app desktop nunca rodou.

## Verificação

- `shellcheck` limpo no template renderizado; script idempotente.
- Três caminhos exercitados: manifest divergente → restaura da origem; legado presente → remove; sem Brave ou sem manifest de origem → `exit 0` com aviso.
- Ponta a ponta na máquina KDE: `desktop_proxy` sobe com o origin da extensão e o log do app registra `Native messaging client 1 has connected` → `Setting up secure channel` → `Biometric unlock for user`.

## Nota operacional

O manifest resolve só o transporte. O app desktop precisa continuar vivo (bandeja + iniciar no login), senão o socket `~/.cache/com.bitwarden.desktop/s.bw` some e a extensão volta a pedir a senha mestra. Documentado em `docs/bitwarden-brave.md`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #25 — fix: keep split-DNS working against the VPN's private resolvers

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `5beda783c`

Branch: `claude/vpn-dot-split-dns` → `main` · 3 arquivos

## Problema

A máquina roda DNS-over-TLS estrito globalmente. Os resolvedores privados da VPN não atendem na porta de DoT, então nome interno não resolvia com o túnel de pé — mesmo com o split-DNS configurado corretamente.

## Solução

`connection.dns-over-tls 0` **só nesse link**. Domínio público continua indo pro Quad9 sobre TLS e nunca chega no resolvedor da empresa, porque os routing domains do split-DNS (`~dominio`) continuam no lugar — é o `Default Route: no` no `tun0` que segura isso.

Junto vai uma guarda que aborta o script se o KCM de rede do KDE estiver aberto. Ele mantém uma cópia inteira do perfil em memória; clicar em Aplicar depois do script restaura `never-default=no` silenciosamente e quebra o split-tunnel de novo — falha chata de diagnosticar porque nada no log indica que foi a janela de configurações.

## Verificação

- `shellcheck` limpo.
- A guarda foi exercitada nos dois caminhos (KCM aberto → `exit 1` com instrução; fechado → segue).
- Runbook atualizado com o sintoma: o link precisa mostrar `-DNSOverTLS` no `resolvectl status tun0`, junto do `Default Route: no` que já estava documentado.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #26 — fix: let Spectacle publish the screenshot during the capture

`MERGED` · @rodolfocamara · aberto 2026-07-27 · merged 2026-07-27 · `3832c275a`

Branch: `claude/screenshot-clipboard-capture` → `main` · 2 arquivos

## Contexto

O `chezmoi status` mostrava `MM` nesses dois arquivos, e o `chezmoi apply` recusou com *"has changed since chezmoi last wrote it"*. Investigando: a versão em `$HOME` é mais nova que a do repo, e `--copy-image` **nunca esteve versionado** (`git log -S` não acha). Era trabalho manual feito na máquina que nunca foi capturado de volta — aplicar teria destruído.

Este PR captura o que está rodando, na direção certa.

## Mudança

O #18 passou `--output` pra garantir a gravação, mas com isso a imagem só chega no clipboard num passo separado. Deixando o Spectacle copiar a imagem como parte da captura, app gráfico cola na hora sem polling; o script continua persistindo o mesmo PNG e expondo só o caminho pela seleção primária, pros terminais.

O comentário do `.desktop` volta a descrever o comportamento real. Ele é template, então `chezmoi re-add` pula e precisou ser editado na mão.

## Verificação

- `shellcheck` limpo; `desktop-file-validate` OK no template renderizado.
- `chezmoi status` não lista mais nenhum dos dois.
- Não testei o fluxo de captura de ponta a ponta — o conteúdo veio de `$HOME`, onde já estava em uso.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #27 — fix: bridge Bitwarden into every Brave data dir, not just the default

`MERGED` · @rodolfocamara · aberto 2026-07-28 · merged 2026-07-28 · `782be5644`

Branch: `claude/bitwarden-brave-work-datadir` → `main` · 2 arquivos

## Problema

Correção do #24, que ficou pela metade.

Os PWAs de trabalho (Teams, Outlook, Azure DevOps, Portal RH) não rodam no Brave normal. Os `.desktop` deles sobem com:

```
--user-data-dir=/home/rcamara/.config/BraveSoftware/Brave-Browser-Work
```

Isso é uma árvore de dados inteiramente separada: extensões próprias, cookies próprios e `NativeMessagingHosts/` próprio. O #24 escreveu o manifest só em `Brave-Browser/`, então:

- Brave pessoal → destrava pelo app desktop ✅
- Brave do trabalho → `NativeMessagingHosts/` **nem existia**, extensão caindo na senha mestra ❌

E nada na UI diferencia as duas — é a mesma extensão, com o mesmo ícone.

## Solução

Iterar sobre `~/.config/BraveSoftware/Brave-Browser*` em vez de tratar um caminho fixo. Pega o pessoal, o `-Work`, e de quebra qualquer Beta/Nightly ou data-dir futuro.

## Verificação

- `shellcheck` limpo no template renderizado.
- No-op quando os dois já estão no lugar; apaguei o do `-Work` e rodei de novo → `bitwarden-brave: ponte instalada em Brave-Browser-Work`.
- `ls ~/.config/BraveSoftware/Brave-Browser*/NativeMessagingHosts/com.8bit.bitwarden.json` lista os dois.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #28 — feat: point every Brave launcher at the flag-reading wrapper

`MERGED` · @rodolfocamara · aberto 2026-07-28 · merged 2026-07-28 · `93b4823e0`

Branch: `claude/normalize-brave-launchers` → `main` · 2 arquivos

## Problema

`/usr/bin/brave` é um wrapper: lê `~/.config/brave-flags.conf`, monta a lista de flags e faz `exec` no binário real. `/opt/brave-bin/brave` é esse binário cru e não lê arquivo nenhum.

12 dos 19 lançadores chamavam o caminho de `/opt`, então `--password-store=basic` e `--enable-features=FedCm` valiam em algumas janelas e não em outras. O Teams chegava a ter dois `.desktop` para o mesmo `app-id`, um por cada caminho.

Isso não é a causa do problema de login no Teams que originou a investigação — os 572 cookies dos dois perfis são todos `v10`, então não há divergência de chave de criptografia. É inconsistência real, mas de outra natureza.

## Solução

Reescreve o prefixo do `Exec=` em cada `~/.local/share/applications/brave-*.desktop`, preservando os argumentos (`app-id`, `user-data-dir`, `%U`) e cobrindo também os grupos `[Desktop Action]`, que carregam `Exec=` próprio.

Dois detalhes que valem a leitura:

- **O gatilho é o hash das linhas `Exec=`**, não a versão do pacote. O Brave gera os `.desktop` dos PWAs apontando pro próprio executável — sempre o de `/opt` — então isso volta a divergir a cada PWA reinstalado. Com esse hash, mexeu num lançador, o script roda de novo.
- **A validação compara antes contra depois**, em vez de exigir arquivo válido. Alguns lançadores que o Brave gera já nascem inválidos (`brave-TOTVS_MY_HR.desktop` tem uma chave `URL` sob `Type=Application`); barrar por estado absoluto recusaria consertar justamente os arquivos problemáticos.

## Verificação

- `shellcheck` limpo.
- 13 arquivos corrigidos; segunda execução é no-op.
- `diff -r` contra backup: **só** linhas `Exec=` mudaram, nada mais.
- O `.desktop` do Outlook tem 4 linhas `Exec=` (menu de ações) — as 4 trocadas.
- Permissões preservadas em 0644, sem temporários vazados.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---

## #29 — feat: give the work Brave profile its own icon

`MERGED` · @rodolfocamara · aberto 2026-07-28 · merged 2026-07-28 · `15c95fa9e`

Branch: `claude/brave-work-icon` → `main` · 4 arquivos

## Problema

As duas instâncias do Brave rodam o mesmo binário e o mesmo tema de ícone. Na barra de tarefas, a janela do trabalho e a pessoal são idênticas — não dá pra saber qual é qual sem clicar.

## Solução

Gira a matiz do ícone do pacote pra azul. Comparei as alternativas em 128px, 48px e 24px: matiz se mantém legível em todos, enquanto selo ou letra viram borrão em 24px, que é o tamanho da bandeja.

O `brave-work-browser.desktop` já tinha `StartupWMClass=brave-work-browser`, então trocar o `Icon=` pega no menu **e** na janela/barra de tarefas, sem mexer em mais nada.

Duas decisões que valem explicar:

- **Deriva do ícone do pacote, não commita PNG.** Mesmo princípio do manifest do Bitwarden no #24: se o Brave mudar a arte num update, a variante acompanha sozinha. O hash do gatilho é o arquivo de origem, então o update dispara a regeração.
- **O `.desktop` entra no repo.** Ele era local, mas a mudança de `Icon=` precisa sobreviver a uma máquina nova. Vai junto dos outros lançadores de trabalho já versionados, e entra no gate de perfil `kde` no `.chezmoiignore`, seguindo o padrão deles.

`imagemagick` entra no `pacman.txt` — já estava instalado na máquina, mas não declarado.

## Verificação

- `shellcheck` limpo; `desktop-file-validate` OK no lançador.
- 7 tamanhos gerados (16 a 256); segunda execução é no-op; sem temporários vazados.
- Degrada limpo: sem `magick` ou sem o ícone de origem, sai com aviso e `exit 0` em vez de quebrar o apply.

---

## #30 — feat: group the work Brave launchers and drop the duplicates

`MERGED` · @rodolfocamara · aberto 2026-07-28 · merged 2026-07-28 · `7d3af61c7`

Branch: `claude/brave-menu-organization` → `main` · 11 arquivos

## O que eu tinha entendido errado

A premissa inicial era que 10 lançadores estavam "sem categoria, caindo num balde genérico". Falso: o Brave já cria `~/.config/menus/applications-merged/user-chrome-apps.menu` e agrupa as 12 PWAs em **"Brave Browser Apps"**. O arquivo tem um aviso de "do not edit manually" e é regerado pelo `xdg-desktop-menu` a cada PWA instalada.

O problema real é que esse grupo único **mistura trabalho e pessoal** (3 pessoais, 9 de trabalho). E o menu já tinha customização manual via `kmenuedit`, num `applications-kmenuedit.menu` que posiciona alguns lançadores no Internet.

Conclusão: não competir com o arquivo do Brave. Este PR trabalha em volta dele.

## Mudanças

**Grupo "Trabalho"** com os 5 lançadores curados do perfil Work. `Categories=` sozinho não cria seção nenhuma — a spec XDG exige também um `.menu` declarando o submenu e um `.directory` com nome e ícone. Os três estão versionados.

**Duplicatas ocultas por detecção, não por lista.** O script procura `app-id` presente em mais de um lançador e põe `NoDisplay=true` só no de nomenclatura gerada pelo Brave. Assim um PWA futuro que ganhe lançador curado é tratado sem mexer no script. Hoje isso pega o Outlook; o Teams já estava oculto à mão.

Escopo deliberadamente estreito: **só duplicata de `app-id` idêntico**. O Azure DevOps tem dois lançadores mas com mecanismos diferentes (`--app=URL` contra PWA instalada), e o TOTVS MY HR aponta pro deep link `#/absence` enquanto o Portal RH abre a raiz — nenhum dos dois é duplicata, e ficam visíveis.

`NoDisplay` em vez de apagar porque ele **também tira do KRunner**. Ocultar as 12 deixaria Figma, Scoreplan e as outras inacessíveis pelo Alt+Space.

**Cópia na área de trabalho é removida**, mas só quando existe arquivo de mesmo nome em `applications/`. Atalho que exista apenas no desktop foi posto ali de propósito e fica.

**Apps (Trabalho)** e **Apps (Pessoal)** abrem `brave://apps` do data-dir correspondente.

## Verificação

- `shellcheck` limpo; `desktop-file-validate` OK nos dois lançadores novos; `.menu` valida como XML.
- `kbuildsycoca6 --menutest` confirma o grupo com os 5 lançadores certos.
- Normalizador rodado: ocultou só o Outlook gerado, curados intactos, segunda execução no-op.
- `--app=brave://apps` testado em perfil descartável antes de virar lançador.

## Consequência a saber

Os lançadores de trabalho mantêm as categorias originais (`Office`, `Development`, `Network`), então aparecem **tanto** na seção funcional **quanto** em Trabalho. Se preferir que apareçam só em Trabalho, é remover a categoria principal de cada um — mudança de uma linha por arquivo. Mantive as duas porque, se o `.menu` custom não for lido algum dia, o lançador ainda tem onde cair.

---

## #31 — fix: keep the menu directories at 0700

`MERGED` · @rodolfocamara · aberto 2026-07-28 · merged 2026-07-28 · `84d09873f`

Branch: `claude/menu-dir-perms` → `main` · 2 arquivos

Sequela do #30. O KDE e o `xdg-desktop-menu` criam `~/.config/menus` e `~/.local/share/desktop-directories` como 0700. Sem o prefixo `private_`, o chezmoi assume 0755 como alvo e afrouxa os três a cada apply — aparecia como `M` permanente no `chezmoi status`, e numa máquina nova seria um afrouxamento silencioso.

Verificado: `chezmoi target-path` confirma que os alvos não mudaram, e o `chezmoi status` não acusa mais diferença nesses diretórios.

---

## #32 — feat: install the AUR list, add uv + headlamp, and a gitignored artifacts/

`OPEN` · @rodolfocamara · aberto 2026-07-29

Branch: `claude/ntfs-linux-wsl-mount-79a2b2` → `main` · 6 arquivos

## O que muda

Dois achados independentes, saídos da migração do ambiente do WSL para o Linux nativo.

### `packages/aur.txt` era código morto

O arquivo existia no repo desde sempre, mas nenhum script o lia — o `install-packages.linux-arch.sh` resolvia apenas `pacman.txt` e `pacman.<profile>.txt`. Qualquer pacote escrito ali era inerte, o que é pior que não ter o arquivo: parece versionado e não instala nada.

O instalador agora lê o `aur.txt` e usa `paru` ou `yay`. Três detalhes:

- O helper roda **como o usuário, sem `sudo`** — ele eleva sozinho só na hora de instalar o pacote já construído. Com `sudo`, o build aconteceria como root.
- Máquina sem helper continua instalando o resto da lista normalmente; os pacotes de AUR são só reportados.
- `--dry-run` mostra as duas listas separadas.

Dois pacotes entram junto:

- **`uv`** (repo oficial) — uma `.venv` criada em outra máquina fica com o symlink do interpretador pendurado; sem `uv` não há como refazer.
- **`headlamp-bin`** (AUR) — GUI de Kubernetes no lugar do Lens. É o projeto do Kubernetes SIG UI, sucessor do `kubernetes/dashboard`, que foi arquivado. Não existe nos repos oficiais; as alternativas de repo (k9s) são TUI.

### `artifacts/` para material sensível

Este repositório é **público**. Certificado de CA interna, kubeconfig e recortes de `/etc` da máquina não podem ser commitados — mas é justamente esse material que falta para deixar uma máquina nova pronta.

`artifacts/` fica dentro do repo, à mão dos scripts, e nunca sai daqui.

**Precisa das duas entradas de ignore, não de uma.** O `.gitignore` esconde do git; não esconde do chezmoi, cujo destDir é sempre o home. Sem a linha no `.chezmoiignore`, um `chezmoi apply` criaria `~/artifacts/` com uma cópia de tudo — mesma armadilha que já vale para `etc/`.

`docs/artifacts.md` registra também o que **não** guardar ali: nada derivável (kubeconfig vindo de `terraform output` envelhece e vira dúvida sobre qual é o bom) e nada que precise sobreviver à máquina — para isso o repo já tem criptografia com age.

## Verificação

- `bash -n` e `shellcheck` limpos no instalador.
- `--dry-run` lista as duas seções corretamente (`uv` na base, `headlamp-bin` no AUR).
- `git check-ignore` e `git status` confirmam que `artifacts/` é invisível ao git.
- `chezmoi ignored` lista `artifacts`, e `chezmoi apply --dry-run` não cria nada em `~`.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

---
