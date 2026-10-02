---
name: dotfiles-change
description: "Prepara e valida mudanças no repositório público dotfiles, com dry-run, higiene de arquivos e autoria, sem aplicar mudanças no host fora do escopo autorizado. Use ao alterar scripts, templates do chezmoi ou pacotes deste repositório."
---

# Dotfiles change

Read current AGENTS.md, machine profile and the relevant script/template. Determine whether the path is a chezmoi target or repository support material; do not accidentally deploy scripts/docs/etc as home files.

Keep employer references and sensitive material out of file content, commit subject/body and author/committer email. Use the repository's current public-safe identity and hygiene CI. Do not import company skills, internal tool output, credentials or private histories into this public repository.

Preserve script idempotence, supported-platform detection, user-level execution and --dry-run. Use sudo only for the narrow required operation; do not run an entire bootstrap as root. Secret files must be private at creation, not after a write.

Before delivery, run repository-required shellcheck and:
```bash
./scripts/install-packages.linux-arch.sh --dry-run
```
Read .github/workflows/ci.yml for current template-rendering and hygiene checks. Do not invent a generic npm test for this repository.

Use chezmoi diff or an available render/dry-run for affected targets before applying. The user's instruction to edit a tracked file does not automatically authorize package installs, /etc changes, services, input remapping, session restart or other persistent host actions.

Finish authorized repository work first. When host application requires an ungranted action, present the exact target and reviewable change. Reuse an explicit approval already given for that target; avoid repeated confirmations.

Report changed files, validation and whether the host was actually modified. Keep English identifiers/commit subjects and Portuguese comments/docs as the repository requires.
