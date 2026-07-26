# Mouse Bluetooth depois do wake

O mouse desta máquina é um Logitech MX Master 3S Bluetooth LE, endereço
`DC:8E:F7:60:E6:59`, ligado ao adaptador Intel AX211 (`btusb`).

## Assinatura da falha

Depois que o PowerDevil apaga as telas, o mouse não volta. O bond não foi
perdido: `bluetoothctl info` ainda mostra `Paired`, `Bonded`, `Trusted` e
`WakeAllowed`, mas `Connected: no`. Uma tentativa direta de `connect` fica
parada. No mesmo estado, o controlador pode ficar preso em discovery e o
journal do BlueZ registrar `Failed to set mode: Busy`.

Não remova o dispositivo nesse caso. Isso descarta um bond válido e obriga a
segurar o botão Easy-Switch para parear novamente.

## Recuperação manual

```bash
fix-bluetooth-mouse DC:8E:F7:60:E6:59
```

O comando segue esta ordem:

1. confirma que o bond ainda existe;
2. tenta uma conexão normal por 10 segundos;
3. somente se ela falhar, desliga e religa o controlador;
4. reconecta o mouse e tenta restaurar os dispositivos que estavam conectados
   antes do reset, como os fones.

Ele nunca chama `bluetoothctl remove` nem `pair`. Se o mouse estiver desligado,
no canal Easy-Switch errado ou tiver realmente perdido a chave do lado dele, o
comando falha sem destruir o estado salvo no Linux.

## Recuperação automática

`fix-monitor-after-resume.service` chama o comando acima depois de cada
desbloqueio ou resume, junto do reparo do monitor. Logs:

```bash
journalctl --user -u fix-monitor-after-resume.service
```
