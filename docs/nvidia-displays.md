# Telas externas com driver NVIDIA

Máquina Lenovo híbrida (Intel Iris Xe + RTX 3060 Mobile), KDE Plasma no
Wayland, driver proprietário `nvidia-580xx-dkms`. As duas telas externas
penduram na NVIDIA (`card2`); o painel do notebook fica na Intel (`card1`).

Dois problemas distintos moram aqui. Eles se parecem — os dois dão tela preta —
mas a causa e o conserto não têm nada a ver um com o outro.

## Problema 1: liga o monitor e não vem imagem

Você liga a tela externa, o KDE mostra ela como `connected` e `enabled`, com
resolução e taxa corretas, e mesmo assim o painel fica preto. Parece que o
Linux não reconheceu — mas reconheceu.

É o `nvidia_drm` perdendo a corrida do modeset no hotplug: recebe o HPD, lê o
EDID, monta o output, e nunca completa o link training.

### Como confirmar que é isso

O truque é separar dois canais que passam pelo mesmo cabo:

| Canal | De onde vem a energia | O que significa se responde |
|---|---|---|
| EDID | +5V do próprio cabo | o cabo está bom e o monitor está plugado — **nada além disso** |
| DDC/CI (VCP) | scaler do monitor | o monitor está acordado e processando sinal |

A EEPROM do EDID responde com o monitor apagado, em standby, ou selecionado em
outra entrada. Então "o kernel vê o EDID" não prova quase nada.

```bash
# Acha o barramento I2C de cada tela
ddcutil detect

# O teste que importa: o monitor está acordado?
ddcutil --bus 17 getvcp 60 D6
```

A assinatura do bug é essa combinação:

```
ddcutil detect        →  Display 2: GSM:34GL750:        (EDID lê)
ddcutil getvcp 60 D6  →  DDC communication failed        (scaler morto)
```

EDID lê, DDC/CI não responde. Se **os dois** falharem, o problema é outro —
cabo, porta ou o monitor em si.

Um segundo sinal, no journal: o conector reassertando em rajada.

```bash
journalctl -b | grep -i 'org_kde_powerdevil' | grep prop_hotplug
```

### O conserto

```fish
fix-monitor
```

A função está em `dot_config/fish/functions/fix-monitor.fish`. Ela troca o
modo do output para o menor disponível e volta para o original — o que força
um modeset novo e faz o link engatar.

```fish
fix-monitor              # toda tela externa ligada
fix-monitor HDMI-A-1     # só essa
fix-monitor --dry-run    # só mostra os comandos
```

O painel do notebook (`eDP-*`) fica de fora de propósito: o bug é do link
externo, e é nele que você vai ler o erro se algo der errado.

Precisa de `jq` e `kscreen-doctor` — KDE only. Na máquina Hyprland a função
existe mas recusa rodar; fish só carrega função de `functions/` quando ela é
chamada, então não custa nada lá.

Na mão, sem a função:

```bash
kscreen-doctor output.HDMI-A-1.mode.1920x1080@60
kscreen-doctor output.HDMI-A-1.mode.2560x1080@144
```

### Antes de culpar o driver

Vale descartar o lado do monitor primeiro, mas sem inventar opção: o OSD varia
bastante entre linhas da LG. No 34GL750 o menu `General` tem Language, SMART
ENERGY SAVING, Power LED, Automatic Standby, HDMI Compatibility Mode,
DisplayPort 1.4, OSD Lock, Information e Reset.

Nenhuma delas explica a assinatura EDID-lê/DDC-morto:

- **Automatic Standby** desliga o monitor por inatividade. Nada a ver com link.
- **HDMI Compatibility Mode** é o único que mexe no link: `Enable` força
  HDMI 1.4, `Disable` libera HDMI 2.0. Só que dá para inferir sem abrir o OSD —
  2560x1080@144 a 8bpc pede ~12 Gbps depois do encoding, e HDMI 1.4 teto em
  10,2 Gbps. Se estivesse em `Enable`, o modo de 144Hz nem apareceria na lista
  de modos do `kscreen-doctor`.

O `Deep Sleep Mode` que corta o scaler e mantém a EEPROM viva — esse sim
produziria a assinatura — existe em outras linhas da LG (UltraFine, monitores
de escritório), **não** nesta. Se você chegar aqui com outro monitor, procure
por ele antes de ir mexer em driver.

## Problema 2: volta do suspend com tela preta

Esse é latente — não aparece até você suspender com os monitores ligados.

O pacote `nvidia-utils` já liga a preservação de VRAM:

```
/usr/lib/modprobe.d/nvidia-sleep.conf
options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/var/tmp
```

Mas quem de fato **grava** essa VRAM em `/var/tmp` antes de suspender é o
`nvidia-suspend.service` — e ele vem desabilitado. O driver promete preservar
e ninguém salva.

O hook de sleep do pacote não tapa esse buraco. Fora do caso especial de
suspend-then-hibernate, `/usr/lib/systemd/system-sleep/nvidia` trata um gancho só:

```sh
case "$1" in
    post)
        /usr/bin/nvidia-sleep.sh "resume"
        ;;
esac
```

Só `post`. Não existe ramo `pre`. O lado do **resume** está coberto pelo hook;
o lado do **suspend** não está coberto por ninguém.

Em `s2idle` isso passa batido. Em S3 a VRAM se perde de verdade:

```bash
cat /sys/power/mem_sleep
# s2idle [deep]    ← deep é o ativo aqui
```

### O conserto

```bash
./scripts/setup-nvidia-sleep.sh
```

Habilita `nvidia-suspend.service` e `nvidia-resume.service`. Idempotente, tem
`--dry-run`, e vale no próximo suspend sem reiniciar.

### Por que hibernate fica de fora

`nvidia-hibernate.service` pendura em um alvo só:

```
[Install]
WantedBy=systemd-hibernate.service
```

E nesta máquina esse alvo está mascarado de propósito:

```
/etc/systemd/system/systemd-hibernate.service -> /dev/null
```

Habilitar seria criar um link para um gancho que nunca dispara. O script
detecta o mask e pula sozinho — numa máquina onde hibernate estiver ativo, ele
inclui a unit.

`nvidia-resume.service` é outra história apesar do nome. Ele pendura em três
alvos, e um deles é `systemd-suspend.service`, que está vivo. Habilitar não
liga hibernação nenhuma.

Resíduo conhecido e inofensivo: o cmdline ainda carrega `resume=UUID=...` e o
`mkinitcpio.conf` ainda tem o hook `resume`. O initramfs procura imagem, não
acha, segue — `PM: Image not found (code -22)` no log de boot.

## Verificar

```bash
# Serviços de sleep
systemctl is-enabled nvidia-suspend.service nvidia-resume.service

# modeset (precisa de root para ler)
sudo cat /sys/module/nvidia_drm/parameters/modeset

# Estado dos conectores, direto do kernel
for p in /sys/class/drm/card*-*/status; do
  printf '%s: %s\n' "${p%/status}" "$(cat "$p")"
done

# O que o KDE acha que está ligado
kscreen-doctor -o
```
