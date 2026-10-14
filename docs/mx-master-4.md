# MX Master 4 no KDE

O botão lateral acima de avançar/voltar emite `BTN_FORWARD` (277) na conexão
Bluetooth. O perfil `handy-desktop` do input-remapper transforma somente esse
botão em F13, usado pelo Handy. O perfil antigo do MX Master 3S é independente.

## Feedback tátil

A vibração associada ao botão de voz está desativada por preferência do usuário.
O serviço `mx4-haptics.service` está parado, sem link de início automático.
O mapeamento F13/Handy permanece ativo e independente.

O pacote `solaar` e o helper `mx4-haptics` permanecem disponíveis para testes
ou uma futura integração. O pulso `SUBTLE COLLISION` foi percebido a 100%;
a intensidade inicial de 25% não foi perceptível.

O helper observa somente o relatório de botões do MX Master 4 Bluetooth
(`046D:B042`), sem capturar o dispositivo ou gerar teclas. Movimentos e conteúdo
digitado não são registrados. Esta integração não cobre o receptor Bolt.
Os alvos pertencem ao perfil `kde` do chezmoi.

Para detectar o dispositivo sem vibrar ou alterar configurações:

```bash
mx4-haptics --dry-run
```

Um teste manual, quando desejado, emite somente um pulso:

```bash
mx4-haptics --test --level 100 --waveform 'SUBTLE COLLISION'
```

## Alertas de conclusão do T3 Code

`t3-haptics.service` monitora novas chamadas `Notify` no D-Bus da sessão com
resumo exato `Thread completed`. Confirma que o processo remetente executa
`/opt/t3code-bin/t3code`, então emite o pulso `SUBTLE COLLISION` a 100% pelo
helper. Outras aplicações, aprovações, erros e mensagens intermediárias são
ignorados. Conclusões dentro de cinco segundos produzem no máximo um pulso.
Não há consulta ao histórico, replay ou fila para quando o mouse reconectar.
Títulos de threads e corpos de notificações não são registrados.

Na versão inspecionada, o T3 só envia essa notificação quando sua janela está
oculta ou sem foco. É necessário escolher `Notifications` em `Thread
notifications` nas configurações do T3 e permitir notificações. O serviço não
altera essa preferência nem reinicia o aplicativo. Uma conclusão de turno não
prova sucesso de CI, merge ou deploy.

Os pacotes `python-dbus`, `python-gobject` e `solaar` fornecem as dependências.
O serviço tem início automático no perfil KDE; o serviço antigo de vibração no
botão de voz permanece desativado.

```bash
t3-haptics --dry-run
systemctl --user status t3-haptics.service
# Desativar os avisos sem alterar o F13:
systemctl --user disable --now t3-haptics.service
```

O teste de integração usa uma notificação local controlada para verificar o
transporte D-Bus e a checagem do executável, sem emitir pulso. A percepção do
pulso do mouse foi validada separadamente. A confirmação com uma conclusão
real do T3 exige as notificações habilitadas e o aplicativo em segundo plano.

## Teste isolado do JuhRadial MX

Em teste manual, sem início automático: tag `v0.4.5-beta.5`, commit
`e3ff44ac8a0f44fe3e6ff0a99f6c2fe01d13048d`, compilado com `cargo build
--release --locked -j 4` em `~/.local/share/juhradial-mx-test`.
O pacote adicional `ydotool` injeta F13 via uinput; Python/PyQt6 já estava
instalado. O daemon e o overlay usam serviços transitórios de usuário.

A cópia de teste tem filtros locais `JUHRADIAL_TEST_EVDEV` e
`JUHRADIAL_TEST_HIDRAW`, resolvidos pela identidade Bluetooth do mouse antes de iniciar.
O detector genérico fica suspenso durante o teste. Isso evita selecionar o
mouse virtual antigo do input-remapper ou observar o touchpad. O supervisor `juhradial-trial-watch` reabre o daemon quando os nós mudam
após reconexão. O listener HID++ não usa outro receptor como fallback no teste.

- O input-remapper do MX Master 4 está parado durante o teste; o preset fica preservado. Seu início automático é suspenso durante o teste
  e restaurado pelo comando de retorno ou ao parar o serviço.
- `buttons.gesture` executa F13 com press/release, sem vibração.
- `buttons.thumb` abre o menu circular no painel Haptic Sense.
- Haptics automáticos, teclado, Flow e início automático estão desativados.
- O menu tem T3, Outlook/Agenda, Chrome Work, Teams, arquivos Dolphin,
  terminal Wave, Chrome Personal e captura, nessa ordem a partir do topo,
  no sentido horário. Trabalho e comunicação ficam à direita; Personal fica
  à esquerda e Arquivos embaixo. Configurações seguem acessíveis pela bandeja.
- Os oito itens usam os ícones dos aplicativos instalados. Work tem o ícone
  azul com maleta e Personal mantém o Chrome colorido, além dos nomes
  distintos. As posições são fixas e não mudam conforme a frequência de uso.
- Arquivos executa `dolphin --new-window`, inclusive quando já há uma janela.
  Wave usa seu arquivo `.desktop`; a captura continua com `spectacle -r`.
- `desktop-app-focus` recebe `t3`, `work`, `personal`, `teams` ou `outlook`.
  Ativa a janela existente pelo KWin, inclusive se minimizada ou em outro
  desktop virtual, mantendo seu monitor. O T3 também aceita o atalho anterior
  `t3code-focus`, que encaminha para esse helper. Chamar apenas o binário do T3
  não trouxe sua janela para frente no teste.
- Havendo várias janelas do mesmo aplicativo, o script no KWin acompanha a
  última ativada. Na primeira execução da sessão, antes de haver histórico,
  parte da ordem visual e prioriza janelas não minimizadas. Guarda só IDs e
  ordem na RAM, sem títulos, URLs ou conteúdo. O Python termina após cada
  comando; não há outro processo residente. O script é carregado no primeiro
  uso e permanece no compositor para acompanhar as próximas ativações.
- Chrome Work e Personal são identificados separadamente das PWAs de Teams e
  Outlook. Só quando não há janela correspondente o helper chama o lançador
  existente. Uma falha ao consultar o KWin não aciona um lançador alternativo,
  evitando duplicatas. Outlook/Agenda retoma a tela em que o usuário parou;
  não navega para outra URL nem abre outra janela de calendário.
- A personalização modifica somente os itens do menu. O tema escolhido,
  as preferências de aparência e os botões permanecem preservados. A cópia
  anterior fica em `~/.local/share/juhradial-mx-test/menu-before-customization.json`.
- `t3-haptics.service` permanece separado; depende das notificações do T3.

Os serviços são `juhradial-trial`, `juhradial-trial-overlay` e
`juhradial-trial-ydotool`. O primeiro restaura os desvios HID++ anteriores ao
parar. Para encerrar o teste e restaurar também o input-remapper:

```bash
juhradial-trial-restore --dry-run
juhradial-trial-restore
```

Medição inicial com a tela bloqueada, menu ainda não exercitado: soma de PSS
aproximadamente 50 MiB (Rust 6,7 MiB, overlay Qt 43,5 MiB, ydotool 0,13 MiB).
PSS divide páginas compartilhadas entre processos; o RSS somado é maior.
Não é um benchmark do consumo com animações ou tela de configurações aberta.
O usuário confirmou a abertura física do menu e o funcionamento do F13/Handy.

Em 13/10, a primeira tentativa física falhou após a conexão Bluetooth mudar de
nó hidraw. O daemon estava ativo, mas escutava um receptor errado; o
input-remapper também havia voltado por autoload. Corrigido no teste com
redescoberta pela identidade Bluetooth, proibição de fallback para outro
receptor e suspensão reversível do autoload do MX4. Aceitação física confirmada
pelo usuário. Após a personalização, o carregador do overlay reconheceu os oito
itens. Após o refinamento, o KWin confirmou a ativação das janelas já existentes
de T3, Work, Personal, Teams e Outlook, com os mesmos IDs. Um teste alternando
entre as duas janelas de Personal confirmou a seleção da última usada, mesmo
após passar pelo T3. A seleção física dos novos itens
ainda depende do próximo uso. O início automático do menu continua desativado
durante este teste.
