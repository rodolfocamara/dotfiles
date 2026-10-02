# Claude Profiles

This repo keeps Claude Code split into two user-scoped profiles:

- `~/.claude-personal`
- `~/.claude-work`

The split is enforced with `CLAUDE_CONFIG_DIR`, so the active shell does not need
to share a single `~/.claude` directory across personal and work contexts.

## Shell entrypoints

Available commands after apply:

- `claude-personal`
- `claude-work`
- `claude` -> defaults to `claude-personal`

The helper commands live in `~/.local/bin`.

## Roteamento por projeto

O comando `claude` usa `personal` por padrão. Um projeto pode ser fixado no
perfil `work` sem depender de lembrar qual wrapper chamar:

```bash
claude-profile set work ~/Repos/project
claude-profile resolve ~/Repos/project
claude-profile list
```

O mapeamento fica em `~/.config/claude-code/project-profiles.tsv`, nasce com
modo `0600` e não entra no repositório. Isso evita publicar nomes e caminhos de
projetos privados. Em worktrees, o helper resolve o repositório principal, então
o mesmo perfil vale para todas as worktrees.

`claude-personal` e `claude-work` continuam disponíveis para uma escolha
explícita e sempre prevalecem sobre o mapeamento.

## Contexto compartilhado entre agentes

`agent-context-sync` mantém uma fonte local e privada, fora deste repositório, em
`~/.local/share/agent-context/` (git local, modo `0700`):

- `AGENTS.md`: instruções pessoais. Vira, por symlink, o `CLAUDE.md` de cada perfil do
  Claude Code (`~/.claude`, `~/.claude-personal`, `~/.claude-work`, `~/.claude-glm`), o
  `~/.codex/AGENTS.md`, o `~/.config/opencode/AGENTS.md` e o `~/.gemini/GEMINI.md`.
  Ferramenta ausente na máquina fica de fora.
- `skills/<grupo>/<nome>/SKILL.md`: skills, em dois grupos.

| Grupo | Destinos |
|---|---|
| `comum` | `~/.agents/skills` e os perfis personal, work e glm do Claude Code |
| `trabalho` | `~/.agents/skills` e os perfis personal e work do Claude Code |

`~/.agents/skills` é lido por Codex, Cursor, Gemini e OpenCode. O Claude Code não lê esse
caminho, por isso recebe os links no próprio perfil. Cada skill ganha um link próprio:
um diretório de skills inteiro como symlink faria um perfil herdar as skills de outro, e o
helper converte esse caso em diretório real. Links para skills que saíram da fonte, ou do
grupo daquele destino, são removidos. Arquivo divergente nunca é sobrescrito: o helper
aborta e pede resolução manual. `~/.claude/skills` fica vazio de propósito, porque Cursor e
OpenCode também leem esse caminho e mostrariam cada skill duas vezes.

Skill que depende de um repositório mora no próprio repositório, em
`.agents/skills/<nome>/`, com `.claude/skills/<nome>` como symlink relativo. Este repo faz
isso com `dotfiles-change`. O chezmoi ignora pastas que começam com ponto, então elas não
vão para o home.

As memórias automáticas continuam nativas de cada ferramenta. O helper só habilita as
memórias locais do Codex quando o recurso existe.

### Segredos usados por skills

`agent-secret` entrega um segredo do Bitwarden (via `rbw`, ou `bw` com
`AGENT_SECRET_BACKEND=bw`) a um comando sem exibi-lo. A skill cita só o nome do item:

```bash
PGPASSWORD=$(agent-secret get <item>)        # só capturado em variável
agent-secret exec PGPASSWORD=<item> -- psql …  # ou injetado no ambiente do comando
agent-secret check <item> <item>:username      # confere sem mostrar
```

Campos: `password` (padrão), `username`, `notes` ou uma chave `chave=valor` das notas.

## Desktop e estado legado

O Desktop pessoal preserva seu login em `~/.config/Claude`, mas agora passa
`CLAUDE_CONFIG_DIR=~/.claude-personal` para o Claude Code. O Desktop work usa
`~/.config/Claude-work` e `~/.claude-work`. Assim, Desktop e terminal concordam
sobre os mesmos dois perfis.

No KDE, o perfil work usa o tema `catppuccin-mocha`, configurado separadamente
em `~/.config/Claude-work/claude-desktop-bin.json`. O tema deixa a janela
visualmente distinta sem modificar o perfil pessoal nem o pacote instalado.

`~/.claude` fica apenas como origem legada para migração. Ele não é apagado.

## Sessões e auto memory por projeto

Uma sessão local pode ser copiada entre os perfis sem copiar autenticação,
cookies, configurações ou caches de plugins:

```bash
claude-sync-session <session-id> --from legacy --to work --with-memory --dry-run
claude-sync-session <session-id> --from legacy --to work --with-memory
```

Com UUID e sem caminho de repositório, o helper procura a sessão em todos os
projetos do perfil de origem. `--with-memory` copia também a pasta `memory/` do
repositório. Destinos divergentes nunca são sobrescritos.

Depois da cópia:

```bash
claude-work --resume <session-id>
```

Isso vale para sessões do Claude Code. Conversas comuns do Claude Desktop são
mantidas pelo serviço na conta que as criou e não são migradas por estes helpers.

## Windows and WSL

Do not share the entire Claude state directory between WSL and native Windows.
Claude stores OS-specific session state under directories such as:

- `projects/`
- `sessions/`
- `session-env/`
- `file-history/`
- `tasks/`

Sharing those directly causes path drift between Linux paths and Windows paths and
breaks resume/history behavior.

For native Windows usage with Git Bash, keep separate native Windows profile dirs:

- `C:\Users\<user>\.claude-personal`
- `C:\Users\<user>\.claude-work`

Then sync only the safe profile data from WSL into Windows:

```bash
claude-sync-windows-profiles
```

This sync copies:

- `settings.json`
- `.credentials.json`
- `skills/`
- top-level custom plugin dirs containing `SKILL.md`
- helper commands in `~/.local/bin`
- a managed Claude block into the Windows `~/.bashrc`

It does not copy session history/state folders.

## Custom skills

When using `CLAUDE_CONFIG_DIR`, keep custom skills inside the split profile dirs:

- `~/.claude-personal/skills`
- `~/.claude-work/skills`
- `~/.claude-*/plugins/<name>/SKILL.md` for plugin-style local skills

Legacy `~/.claude/skills` is outside the split and may not be discovered
consistently once the shell points Claude at `~/.claude-personal` or
`~/.claude-work`.

## Windows install

Native Windows Claude Code is a separate installation from the WSL installation.
If you want to run Claude from Git Bash on a Windows-native project, install
Claude Code on Windows as well.

This repo does not force-install Claude Code on Windows because you may already
have it through npm, the native installer, or WinGet, and mixing install methods
creates competing `claude` binaries on `PATH`.

On a fresh Windows setup, install exactly one native Windows Claude Code variant:

```powershell
winget install Anthropic.ClaudeCode
```

Git for Windows is also required for native Windows usage.
