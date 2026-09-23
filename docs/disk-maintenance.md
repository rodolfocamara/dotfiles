# Manutenção de disco

O disco da máquina KDE (btrfs, 308G) enche por três frentes que nenhum timer de
sistema cobre: caches de toolchain no `~/.cache`, clones/builds do paru e
órfãos de compose stacks mortas no podman. Em setembro de 2026 isso chegou a
88% de uso com 66G recuperáveis — a limpeza manual virou o script
`disk-maintenance` (em `dot_local/bin/`), rodado por timer systemd do usuário.

## O que o script limpa

Tudo regenerável — re-download ou rebuild na próxima execução:

- `~/.cache/go-build`, `~/.cache/codex-update-manager`, `~/.cache/codex-runtimes`, `~/.cache/paru` (o `paru -Sc` não alcança este)
- `uv cache clean`
- Podman: containers exited (`container prune`), imagens sem container (`image prune -af`) e volumes anônimos (`volume prune` sem `--all`)

O que **nunca** é tocado: containers rodando, volumes nomeados (dados de
bancos de compose stacks pausadas ficam lá), caches de navegadores (o app
está aberto quando o script roda).

## Arquivo de caminhos extras

`~/.config/disk-maintenance/extra-caches.list` — um caminho por linha,
comentários com `#`. Fica fora do repo de propósito: caminhos variam por
máquina e podem nomear projetos de trabalho. Entrada lá é apagada só se
nada dentro foi modificado há mais de 14 dias (não queima cache de projeto
ativo).

```
# um caminho por linha; ~ expande
~/.cache/algum-projeto
```

## Timers que já existem (não duplicar)

- `paccache.timer` (sistema, segundas 00:00) — cache de pacotes do pacman
- `snapper-cleanup.timer` — poda os snapshots `number` a cada ciclo

## Operação

```
disk-maintenance --dry-run   # relatório sem apagar
systemctl --user list-timers disk-maintenance.timer
journalctl --user -u disk-maintenance
```

O timer roda segundas ~09:17 (com até 15min de atraso aleatório),
`Persistent=true` cobre máquina desligada no horário.