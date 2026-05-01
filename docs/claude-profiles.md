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

To merge legacy/shared custom skills and keep both profiles aligned:

```bash
claude-sync-skills
```

This sync copies only custom skills and top-level local plugin skills. It does
not touch conversations, session state, or plugin caches.

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
