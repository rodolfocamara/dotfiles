# Manutenção de disco

A manutenção combina poda horária de imagens sem container, limpeza diária de
caches conhecidos e limites de logs/pacotes. Roda como usuário, com lock para
impedir duas execuções simultâneas. Nesta máquina, `docker` é um shim para
Podman; o script gerencia o store Podman do usuário, não um daemon Docker
nativo nem o store de root.

## Política

| Alvo | Rotina | Quando o espaço aperta |
|---|---|---|
| Imagens Podman sem qualquer container | A cada hora, criação há mais de 72h | Criação há mais de 24h |
| Arquivos em `go-build`, `pip`, `~/.npm/_cacache` | Diariamente, sem escrita há 7 dias | Sem escrita há 24h |
| uv | `uv cache prune --ci` diário | Repete a cada execução |
| Clones/builds do paru | Diretórios sem arquivos escritos há 7 dias, sem paru/yay/makepkg/pacman ativo | Mesma proteção |
| Pacman | Poda diária, guarda 2 versões por pacote | Mesma política |
| Journal, incluindo containers com driver journald | 50 MiB persistente, 50 MiB em RAM, retenção de 14 dias | `SystemKeepFree=20G` |

Pressão significa **75% de ocupação ou menos de 40 GiB livres** em qualquer
filesystem do home, cache ou store Podman. Persistindo após a poda, registra
aviso no journal e tenta notificação no desktop. A notificação é crítica a
**85% ou menos de 20 GiB livres**. Falhas de uma ferramenta não impedem as
outras podas; a unidade termina com erro para tornar a falha visível.

O filtro `until` do Podman usa a **data de criação da imagem**, não a data do
último uso/download. Uma imagem antiga recém-baixada pode ser removida se
nenhum container a referenciar. `disk-maintenance.keep=true` na imagem a
exclui da poda; use `LABEL disk-maintenance.keep=true` no Containerfile quando
precisar manter um build local sem container.

## Proteções e limites

A idade dos caches é baseada na última escrita (`mtime`). Acesso recente
registrado em `atime` também preserva o arquivo, mas **não há garantia de manter
cache apenas por leitura**: neste Linux, `/home` usa `noatime`. Um cache antigo
consultado frequentemente pode ser removido e reconstruído. Essa política não
se aplica a projetos, históricos nem dados dos containers.

- Não remove containers, nem parados, nem volumes anônimos/nomeados. Imagens
  referenciadas por containers ou builds ficam protegidas pelo Podman.
- Não usa `system prune`, `--external` nem `--build-cache`: caches de mounts de
  build em andamento não entram na limpeza automática.
- Não percorre o home nem limpa `.cache` inteiro. Históricos Claude/Codex/T3,
  runtimes de agentes em execução, projetos, navegadores e backups ficam fora.
- A antiga `extra-caches.list` não é mais processada. Só os caches enumerados
  acima entram na automação; uma entrada arbitrária poderia apontar para dados.
- `uv --ci` descarta downloads fáceis de refazer e mantém wheels compiladas;
  não é um teto rígido para esse cache. O script não passa `--force` ao uv.
- Snapshots continuam com o `snapper-cleanup.timer` existente. Não altera sua
  retenção nem apaga snapshots nesta configuração.

São regras de coleta e limites de journal, **não uma quota de disco**: dados de
containers, imagens presas por containers parados, caches recentes e snapshots
podem continuar crescendo. Um build muito grande pode consumir espaço entre
execuções. O alerta pede inspeção, nunca apaga dados para forçar espaço livre.
`df` no Btrfs é uma estimativa; snapshots podem reter blocos após a limpeza.

## Instalação e operação

O chezmoi gerencia script, service e timer do usuário. Depois de aplicar esses
três alvos, recarregue e reinicie o timer para trocar a agenda já carregada:

```bash
systemctl --user daemon-reload
systemctl --user enable disk-maintenance.timer
systemctl --user restart disk-maintenance.timer
./scripts/setup-disk-guards.sh --dry-run
./scripts/setup-disk-guards.sh
```

O segundo script instala apenas drop-ins de journald/paccache, com sudo nas
operações necessárias. É idempotente e pula pacman onde não estiver instalado.
Não é necessário executar o instalador geral de `/etc`.

```bash
disk-maintenance --dry-run
systemctl --user start disk-maintenance.service
systemctl --user list-timers disk-maintenance.timer
journalctl --user -u disk-maintenance.service
systemctl list-timers paccache.timer
```

Timer: de hora em hora, até 5 minutos de atraso aleatório, `Persistent=true`.
Roda enquanto o gerenciador systemd do usuário estiver ativo; o próximo login
recupera uma execução perdida. O dry-run mostra os comandos sem remover arquivos,
criar locks, atualizar marcadores ou enviar notificações. O marcador da poda
diária fica em `~/.local/state/disk-maintenance/last-cache`.

O marcador diário é gravado por substituição atômica. Marcadores vazios,
inválidos ou futuros são tratados como ausência de execução anterior. Falha
ao inspecionar um clone do paru preserva o diretório e sinaliza erro.
