# Modelo de operação

Este repositório configura máquinas reais. Um erro aqui não quebra um teste —
quebra o notebook de alguém no meio do bootstrap, ou vaza um segredo num repo
público. As regras abaixo existem por causa disso.

## O que este repo é

Source dir do [chezmoi](https://chezmoi.io), cobrindo três alvos: Windows, Arch
(KDE e Hyprland) e Linux/WSL. O perfil de máquina decide o que é aplicado — ver
[`docs/machine-profiles.md`](docs/machine-profiles.md).

Nem tudo aqui é alvo do chezmoi. `scripts/`, `packages/`, `docs/` e `etc/` são
estrutura de repositório e estão no `.chezmoiignore`; se entrassem, virariam
`~/scripts`, `~/etc` e por aí. O caso do `etc/` está explicado em
[`scripts/install-etc.sh`](scripts/install-etc.sh).

## Este repositório é público

**Nenhuma menção ao empregador**, em nenhum dos três vetores:

1. conteúdo de arquivo;
2. mensagem de commit — assunto **e** corpo;
3. autoria — `user.email` em `%ae` e `%ce`.

O repo já foi apagado e recriado uma vez por isso. Uma reescrita de histórico
anterior tinha limpado só o vetor 1 e passou batido nos outros dois; e
`git filter-repo` + force-push **não** remove nada do GitHub — os commits viram
órfãos mas continuam sendo servidos por SHA. O job `higiene` do CI checa os três.

Material sensível que precisa ficar por perto vai em `artifacts/`, ignorado pelo
git **e** pelo chezmoi. Ver [`docs/artifacts.md`](docs/artifacts.md).

## Segredo em disco

Todo arquivo com segredo nasce fechado, nunca "abre e fecha depois":

```bash
( umask 077; printf '%s\n' "$secret" > "$file" )
```

Com o umask padrão (022) o redirecionamento cria o arquivo `0644`, e um `chmod
600` na linha seguinte só fecha a porta depois que ela ficou aberta. A janela é
curta e real. `mktemp -d` já cria `0700` e não precisa disso.

## Estilo dos scripts

- `set -euo pipefail` no topo.
- `--dry-run` em tudo que modifica o sistema.
- Idempotente: rodar de novo não estraga nada.
- Roda como o usuário, elevando com `sudo` só onde precisa — nunca o script
  inteiro sob `sudo`. Isso importa para o chezmoi (que leria o home do root) e
  para os helpers de AUR (que buildariam como root).
- Detectar e pular com mensagem quando o alvo não existe naquela máquina, em vez
  de falhar. Ver `install-etc.sh` e `setup-nvidia-sleep.sh`.
- Comentário explica **por quê**, não o quê. Se a linha é óbvia, não comente.

## Idioma

Assunto de commit, nomes de arquivo e identificadores em **inglês**. Corpo do
commit, comentários e `docs/` em **português** — é a língua em que as decisões
foram pensadas, e traduzir custa nuance.

## Antes de commitar

```bash
shellcheck $(git ls-files '*.sh' | grep -v '\.tmpl$')
./scripts/install-packages.linux-arch.sh --dry-run
```

O CI roda shellcheck, renderiza todos os templates do chezmoi e verifica a
higiene. Ver [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
