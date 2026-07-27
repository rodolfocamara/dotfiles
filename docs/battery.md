# Teto de carga da bateria (Legion / IdeaPad)

Máquina: Lenovo Legion 5 15IAH7H (`82TB`), driver `ideapad_laptop`.

## O problema

Bateria de íon-lítio parada em 100% no carregador o dia inteiro degrada mais
rápido do que bateria que passa a vida numa faixa intermediária. No Windows isso
se resolve com um toggle no Vantage (ou no Legion Toolkit). A pergunta é qual é o
equivalente aqui.

## O que este hardware oferece — e o que não oferece

**Não dá para escolher 80%.** Esse número vem de ThinkPad, que expõe
`charge_control_start_threshold` / `charge_control_end_threshold` e aceita o
percentual que você quiser. Nenhum desses nós existe nesta máquina:

```bash
find /sys -name 'charge_control*'    # vazio
find /sys -name 'charge_behaviour*'  # vazio
```

O que o EC oferece é um **liga/desliga**, com o teto definido pelo firmware — a
Lenovo documenta ~55–60% para o conservation mode de IdeaPad/Legion. Não é
ajustável por software; nenhuma ferramenta muda isso, porque a decisão é do
embedded controller.

O driver `ideapad_laptop` expõe o bit em dois lugares, o mesmo estado visto de
duas APIs:

```bash
cat /sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode  # 1 = ligado
cat /sys/class/power_supply/BAT0/charge_types    # Fast Standard [Long_Life]
```

`Long_Life` selecionado == `conservation_mode` em 1.

### Conferir o teto real

Ligar o modo com a bateria já em 100% não descarrega nada — ele só deixa de
carregar. Para ver o teto de fato: desligue da tomada, use até cair abaixo da
faixa, replugue e observe onde `capacity` estaciona com `status` em
`Not charging`.

## O que está versionado

**[`etc/udev/rules.d/90-ideapad-conservation.rules`](../etc/udev/rules.d/90-ideapad-conservation.rules)**
— reaplica `conservation_mode=1` sempre que o device aparece (boot,
`modprobe`), e passa o atributo para `root:wheel` com modo `0664`.

O EC normalmente guarda o estado sozinho, então reaplicar parece redundante. Não
é: um reset de BIOS devolve o padrão de fábrica em silêncio, e a falha é
invisível — nada avisa que voltou a carregar até 100%. Reaplicar custa zero.

**[`dot_local/bin/executable_battery-conservation`](../dot_local/bin/executable_battery-conservation)**
— alterna e mostra o estado. Sem sudo, graças ao `chmod` da regra.

Instalação: a regra vai por [`scripts/install-etc.sh`](../scripts/install-etc.sh)
(bloco guardado — em máquina sem `conservation_mode` ele pula), o script vai por
`chezmoi apply`. No `.chezmoiignore` o helper está no bloco do perfil `kde`,
que é esta máquina; o acoplamento real é com o hardware Lenovo, não com o
desktop, mas perfil é a granularidade que o repo tem.

## Uso

```bash
battery-conservation           # estado + saúde + ciclos
battery-conservation off       # vale até o próximo boot
battery-conservation on
battery-conservation toggle
```

`off` voltar sozinho no reboot é intencional: sair com 100% antes de uma viagem é
a exceção, proteger é o default.

## Verificar

```bash
ls -l /sys/bus/platform/devices/VPC2004:00/conservation_mode   # root wheel 0664
udevadm verify etc/udev/rules.d/90-ideapad-conservation.rules
```

## Alternativas descartadas

**`lenovo-legion-linux-toolkit-release` (AUR).** É o pacote mais popular na
busca por "legion" e é uma armadilha. O PKGBUILD instala um
`/etc/modprobe.d/blacklist-lenovo-legion.conf` que desliga `ideapad_laptop`,
`ideapad_acpi` e todos os `lenovo_wmi_*` — ou seja, mata exatamente o driver que
faz o `conservation_mode` funcionar hoje, para substituir pelo módulo DKMS dele.
Além disso lista `cuda` (~5 GB) como dependência dura e faz `chmod 777` em
diretórios de log/data. Um voto no AUR.

**`lenovolegionlinux-dkms-git` + `lenovolegionlinux-git`** (johnfanv2). Essa é
séria: upstream ativo, pacote `-git` que compila do HEAD, e não faz blacklist —
o projeto lê os arquivos do `ideapad_laptop` em vez de brigar com ele. Ficou de
fora porque o ganho não paga o módulo DKMS recompilando a cada kernel. Power
modes já são nativos no kernel 7.1 via `lenovo_wmi_gamezone`:

```bash
cat /sys/firmware/acpi/platform_profile_choices   # low-power balanced performance custom
```

O que sobra de exclusivo é curva de fan e leitura de RPM das ventoinhas (não há
hwmon de fan hoje — só CPU, NVMe e bateria). Se um dia isso fizer falta, é este
o pacote, não o outro.

**`lenovo-legion-electric-ray-git`.** Faz exatamente rapid charge +
conservation, mas o upstream parou em maio de 2024. Três linhas de udev cobrem o
mesmo caso sem dependência.

**TLP.** Os thresholds de carga do TLP funcionam em ThinkPad (`tpacpi-bat`) e
alguns Dell; ele não mexe em conservation mode de ideapad. E aqui já roda o
`power-profiles-daemon`, com quem o TLP conflita.

**KDE.** O Plasma só mostra limite de carga nas configurações de energia quando
o kernel expõe `charge_control_end_threshold`. Não expõe aqui, então não aparece
— não é bug de configuração.
