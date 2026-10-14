# T3 Code nightly

O lançador `t3code-nightly` usa o AppImage oficial
`0.0.46-nightly.20261014.3093`, verificado pelo SHA-256 publicado no GitHub.
O arquivo fica em `~/.local/opt/t3code-nightly/`. A versão está fixada e o
atualizador automático fica desativado neste lançamento controlado.

## Atualizações

A versão e o SHA-256 ficam em `dot_local/bin/executable_t3code-nightly`.
Baixe o AppImage da release oficial, confira o digest publicado pelo GitHub e
atualize os dois valores antes de aplicar o lançador. Preserve o AppImage
anterior até validar a nova versão. Não basta substituir o arquivo mantendo o
nome antigo: o lançador recusa um checksum diferente.

Na primeira abertura de cada versão o lançador faz o backup sozinho (ver
abaixo). Backups de versões anteriores continuam em disco e podem ser apagados
à mão depois de validar a nova.

O APK Android V2 é publicado na [release android-nightly](https://github.com/pingdotgg/t3code/releases/tag/android-nightly).
Instale o novo APK como atualização do existente. O AppImage e o APK têm
numerações independentes.

O lançador usa `~/.t3`, `~/.config` e os demais diretórios habituais. O menu
T3 Code e a opção do mouse passam pelo arquivo `t3code.desktop`. A estável
permanece instalada; `T3 Code Stable (Recovery)` chama `/usr/bin/t3code`.

## Primeira abertura

```sh
t3code-nightly --dry-run
t3code-nightly --wait-for-stable
```

O segundo comando aguarda o T3 fechar. Não interrompe agentes. Na primeira
abertura de cada versão, exige que nenhum T3 esteja aberto, estável ou qualquer
AppImage, inclusive um aberto fora do lançador: o `flock` só coordena
lançadores e não impede o app de escrever no banco durante a cópia. Então copia
`~/.t3/userdata` e os perfis Electron existentes (`~/.config/t3code` e
`~/.config/t3code-v2`) para `~/.local/share/t3code-backups/before-<versão>-*`,
com permissões restritas e reflinks quando disponíveis. Cada banco presente
(`statev2.sqlite`, `state.sqlite`) passa por `PRAGMA quick_check`, e o
resultado fica em `~/.local/state/t3code-nightly/migration-backup.json`. Falha
de backup ou de checksum impede a abertura. Nas execuções seguintes da mesma
versão, o registro é reaproveitado e uma nightly já aberta recebe o link.

A migração nativa da V2 copia `state.sqlite` para `statev2.sqlite` uma vez.
Projetos, configurações, anexos e worktrees são aproveitados. Conversas feitas
depois em cada versão não são sincronizadas com a outra. A V2 usa um perfil
Electron separado e importa algumas preferências; cookies não são migrados.
Conversas antigas iniciam novas sessões do provedor, com recuperação de
contexto. Nem todos os eventos internos, checkpoints e diffs antigos são
convertidos. Ver [migração oficial](https://github.com/pingdotgg/t3code/blob/v0.0.46-nightly.20261013.3066/docs/user/thread-migration.md).

O helper informa ao serviço de haptics o executável montado pelo AppImage via
`$XDG_RUNTIME_DIR/t3code-haptics.env`. O filtro continua conferindo o processo
remetente da notificação; não confia apenas no nome do aplicativo. Ao sair,
restaura o caminho da estável. F13 e o menu radial não são remapeados.

## Teste isolado anterior

`t3code-nightly-test` continua disponível, com dados em
`~/.local/share/t3code-nightly-test`, mas o atalho fica oculto no menu. Esses
dados não participam da migração. O script mantém `--dry-run` para inspeção.

Um serviço transitório `t3code-nightly-migration` pode aguardar a primeira
troca nesta sessão. Para cancelar a espera, antes de fechar a estável:

```sh
systemctl --user stop t3code-nightly-migration.service
```

Não abra a estável e a nightly deliberadamente juntas depois da troca: embora
tenham bancos distintos, compartilham configurações e arquivos de projetos.
