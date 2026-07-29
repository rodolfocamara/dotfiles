# Contribuindo

## TL;DR

- Commits seguem [Conventional Commits](https://www.conventionalcommits.org/).
- Um assunto por branch, um assunto por commit.
- `shellcheck` limpo antes de todo commit. O CI roda ele, renderiza os templates
  do chezmoi e checa higiene.
- Edição assistida por IA é bem-vinda — o modelo de operação está em
  [`AGENTS.md`](AGENTS.md).
- **Este repositório é público e não pode citar o empregador.** Vale para
  arquivo, mensagem de commit e autoria. Ver `AGENTS.md`.

## Conventional Commits

```
<tipo>[escopo opcional]: <assunto em inglês>

<corpo em português explicando o porquê>
```

### Tipos

`feat` · `fix` · `docs` · `refactor` · `chore` · `ci` · `test` · `perf` · `style`

### Escopos usados aqui

Costumam ser o alvo, não o diretório: `brave`, `nvidia`, `openvpn`, `searxng`,
`waybar`, `kde`, `wsl`, `packages`. Escopo é opcional — a maioria dos commits do
histórico não usa.

### Exemplos do histórico

```
feat: run Wave as the terminal workspace
fix: bridge Bitwarden into every Brave data dir, not just the default
fix: keep split-DNS working against the VPN's private resolvers
```

Repare que o assunto diz o efeito, não o arquivo mexido. "not just the default"
carrega mais informação que "update script".

### Corpo

O corpo é onde mora o valor. Ele responde **por que**, não o que — o diff já diz
o que. Se a mudança corrige algo, diga o que quebrava e como se manifestava.

Foi lendo esses corpos que, em 2026-07, deu para concluir com segurança que uma
branch antiga não tinha nada a resgatar: o `#24` trouxe o trabalho dela e o `#27`
já o havia superado. Corpo vazio teria custado horas de arqueologia.

## Verificação

Antes de abrir o PR:

```bash
shellcheck $(git ls-files '*.sh' | grep -v '\.tmpl$')
./scripts/install-packages.linux-arch.sh --dry-run
./scripts/install-etc.sh --dry-run
```

Todo script que mexe no sistema tem `--dry-run`. Se você escreveu um que não
tem, ele ainda não está pronto.

## Segredos

Nunca commite credencial, certificado de CA interna, kubeconfig ou recorte de
`/etc` da máquina. O que precisa ficar por perto vai em `artifacts/`, que está
nos dois ignores — ver [`docs/artifacts.md`](docs/artifacts.md). O que precisa
sobreviver à máquina é criptografado com age, como em
`etc/openvpn/client/encrypted_client.conf.age`.

Arquivo com segredo nasce fechado, com `umask 077` no subshell. `chmod` depois
da escrita deixa uma janela em que o segredo esteve legível.
