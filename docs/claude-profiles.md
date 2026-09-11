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

## Contexto compartilhado com o Codex

`agent-context-sync` transforma as instruções pessoais existentes em uma fonte
local única, armazenada em `~/.local/share/agent-context/AGENTS.md` com modo
`0600`. Os arquivos abaixo passam a apontar para ela:

- `~/.claude/CLAUDE.md`
- `~/.claude-personal/CLAUDE.md`
- `~/.claude-work/CLAUDE.md`
- `~/.codex/AGENTS.md`

O conteúdo não é versionado. Se algum destino já existir com conteúdo diferente,
o helper aborta em vez de sobrescrever. Arquivos equivalentes recebem um backup
local antes de virarem links. O helper também habilita as memórias locais do
Codex quando o recurso está disponível.

Essa camada contém preferências e instruções estáveis. As memórias automáticas
continuam nativas de cada ferramenta: Claude grava Markdown por repositório e o
Codex mantém seu próprio estado gerado. Elas não são ligadas diretamente porque
os formatos e os ciclos de consolidação são diferentes.

Skills que precisam ter o mesmo comportamento nos três perfis ficam fora deste
repositório, em `~/.local/share/agent-context/skills/<nome>/SKILL.md`. O mesmo
helper cria links para:

- `~/.claude/skills`
- `~/.claude-personal/skills`
- `~/.claude-work/skills`
- `~/.agents/skills`

Isso mantém uma única cópia privada da instrução e usa o diretório de skills de
usuário reconhecido pelo Codex. O helper só aceita nomes portáveis em letras
minúsculas, números e hífens e aborta diante de conteúdo divergente.

Esses links cobrem Claude Code e Codex locais. O Chat comum do Claude Desktop
armazena skills e conectores remotos na conta: uma skill portável precisa ser
empacotada com sua pasta como raiz do ZIP e enviada em `Customize > Skills`;
um MCP remoto precisa ser conectado em `Customize > Connectors`. Em planos
gerenciados, a organização pode exigir habilitação prévia por um Owner.

Nos repositórios, `AGENTS.md` é a fonte canônica para Codex. Um `CLAUDE.md` curto
deve importá-la para Claude:

```markdown
@AGENTS.md
```

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

To merge legacy/shared Claude-only skills and keep both Claude profiles aligned:

```bash
claude-sync-skills
```

This sync copies only custom skills and top-level local plugin skills. It does
not touch conversations, session state, or plugin caches. Prefer
`agent-context-sync` for a new skill that is deliberately compatible with both
Claude and Codex; reserve `claude-sync-skills` for existing Claude-specific
material after reviewing it for conflicts and secrets.

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
