# Runbooks de rede

Sintoma → diagnóstico → comando. Escrito para o Você de daqui a seis meses, que
não vai lembrar por que o DNS está do jeito que está.

**Como a rede desta máquina está montada** (contexto que explica quase todos os
runbooks abaixo):

| Peça | Estado | Onde mexe |
|---|---|---|
| DNS | Quad9 sobre TLS, estrito | `/etc/systemd/resolved.conf.d/dot.conf` |
| DNS do roteador | ignorado no wlan0 | `nmcli` (`ipv4.ignore-auto-dns`) |
| `.local` | avahi/mDNS, **fora** do DNS | `/etc/nsswitch.conf` |
| VPN | NetworkManager, split-tunnel | `scripts/setup-vpn-nm.sh` |
| MAC do wifi | estável por rede, não é o real | `nmcli` (`wifi.cloned-mac-address`) |

**Antes de copiar qualquer comando daqui**, defina estas duas variáveis. Elas
se descobrem sozinhas, e evitam que nome de rede e de empregador fiquem
escritos num repositório público:

```bash
WIFI=$(nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="802-11-wireless"{print $1; exit}')
VPN=$(nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="vpn"{print $1; exit}')
echo "wifi=$WIFI  vpn=$VPN"
```

---

## Wifi público não abre a página de login (portal cativo)

**Por quê:** `DNSOverTLS=yes` é estrito — não cai pra texto puro. O portal
cativo precisa sequestrar o DNS para te mandar pra página de login, e não
consegue. É o preço deliberado de não vazar domínio nenhum.

```bash
sudo resolvectl dnsovertls wlan0 no
```

Loga no portal, e **volta atrás na hora** — senão você fica em texto puro sem
perceber:

```bash
sudo resolvectl dnsovertls wlan0 yes
```

Isso é por link e por sessão: reconectar já restaura o padrão estrito.

---

## DNS parou de funcionar

Na ordem, do mais provável ao menos:

```bash
resolvectl status                                   # DoT ativo? qual servidor?
timeout 5 bash -c '</dev/tcp/9.9.9.9/853' && echo 853-ok
resolvectl query --cache=no github.com
```

- **Porta 853 bloqueada** (hotel, rede corporativa): com DoT estrito nada
  resolve. Use o contorno do portal cativo acima.
- **`Current DNS Server` mostra um IP de roteador**: o link virou rota padrão
  de DNS. Veja o runbook de rede nova, abaixo.
- **Resolve mas `encrypted transport: no`**: está em texto puro. Confira se o
  `dot.conf` sobreviveu a um update — `./scripts/install-etc.sh` reinstala.

Reverter tudo, se precisar da rede funcionando já:

```bash
sudo rm /etc/systemd/resolved.conf.d/dot.conf && sudo systemctl restart systemd-resolved
nmcli connection modify "$WIFI" ipv4.ignore-auto-dns no && nmcli connection up "$WIFI"
```

---

## Rede wifi nova: consultas lentas na primeira vez

**Por quê:** o `ignore-auto-dns` foi aplicado **só no perfil do wifi de casa**. Em
outra rede, o DNS local dela vira rota padrão, o resolved tenta DoT contra um
servidor que não fala DoT, falha, e só então cai no Quad9. Resolve, mas
desperdiça uma tentativa por consulta nova.

```bash
nmcli connection modify <NOME_DA_REDE> ipv4.ignore-auto-dns yes ipv6.ignore-auto-dns yes
nmcli connection up <NOME_DA_REDE>
```

Custo: nomes servidos pelo DNS daquela rede param de resolver. Na rede de casa
isso custou zero — o roteador não serve nome de dispositivo nenhum (verificado
com `dig @<ip-do-roteador> <host>`, resposta vazia).

---

## `<host>.local` (ou qualquer `.local`) parou

**Não é DNS.** O `/etc/nsswitch.conf` resolve `.local` por mDNS antes de
qualquer servidor de DNS, e o `[NOTFOUND=return]` impede que caia pro DNS:

```
hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [...] dns
```

Então o culpado é o avahi, não o resolver:

```bash
systemctl is-active avahi-daemon
avahi-resolve -n <host>.local
avahi-browse -art | grep -oE '[A-Za-z0-9-]+\.local' | sort -u
```

Se o avahi está de pé e o host não aparece, o problema está do outro lado (o
host dormindo, ou em outra VLAN/rede).

---

## VPN conectou e a internet parou

**Por quê:** o perfil voltou a assumir a rota default. Um `.ovpn` importado
cru faz isso — todo o tráfego passa a sair pela rede da empresa.

```bash
ip route show default          # tem que apontar pro wlan0, não pro tun0
```

Conserto (reaplica todos os ajustes, idempotente):

```bash
./scripts/setup-vpn-nm.sh
```

---

## VPN: `AUTH_FAILED`

```bash
journalctl --no-pager --since '-10 min' | grep -iE 'nm-openvpn|vpn\['
```

**Leia o log na ordem certa** — a linha que separa os dois problemas é o
`Peer Connection Initiated`:

| O que aparece | Significa |
|---|---|
| falha **antes** do `Peer Connection Initiated` | certificado ou senha da **chave privada** |
| `Peer Connection Initiated` e depois `AUTH_FAILED` | TLS ok — o servidor recusou **usuário/senha da conta** |

São credenciais diferentes. Se o TLS passou, a senha da chave está certa e não
adianta mexer nela.

Causa mais comum do `AUTH_FAILED` com senha certa — **usuário vazio**:

```bash
nmcli connection show "$VPN" | grep -E 'vpn.user-name|connection-type'
```

Com `connection-type = password-tls` o openvpn manda usuário **e** senha; em
branco, o servidor recusa mesmo com a senha correta.

```bash
nmcli connection modify "$VPN" vpn.user-name 'SEU_USUARIO'
```

Cuidado: falhas repetidas podem bloquear a conta no servidor. Confirme a
credencial antes de insistir.

---

## VPN: `Invalid connection type` / o perfil parou do nada

**Por quê:** o perfil perdeu o `vpn.data`. Sobra o nome, o UUID e a senha, mas
some `connection-type`, `remote`, `ca` — e o plugin recusa.

```bash
nmcli connection show "$VPN" | grep '^vpn.data'
```

Se só aparece `password-flags`, está vazio. Reimporte do `.ovpn`:

```bash
./scripts/setup-vpn-nm.sh
```

O `.ovpn` de origem fica fora do repo — o caminho está em `workVpn.ovpnFile`
no `.chezmoidata.toml`.

---

## VPN não sobe sozinha no boot

Duas causas, e as duas precisam ser resolvidas:

1. **Senha na KWallet.** Com `password-flags = 1` a senha é *agent-owned* e só
   existe depois que você loga na sessão gráfica. No diálogo de senha, marque
   "armazenar para todos os usuários" (vira `0`, guardada no sistema).
2. **A VPN não está encadeada na wifi.** O `connection.secondaries` é lista de
   **UUID**, não de nome — passar o nome não funciona:
   ```bash
   nmcli connection modify "$WIFI" connection.secondaries \
       "$(nmcli -g connection.uuid connection show "$VPN")"
   ```

Conferir os dois:

```bash
nmcli -g connection.secondaries connection show "$WIFI"
nmcli connection show "$VPN" | grep -o 'password-flags = [0-9]'
```

---

## Split-DNS da VPN: conferir se ainda vale

Depois de conectar. O `Domains=~.` global é rota padrão, mas domínios de
roteamento mais específicos ganham dele — é isso que mantém a divisão:

```bash
resolvectl status tun0 | grep -E 'Default Route|DNS Domain'
resolvectl query --cache=no <dominio-interno>   # -- link: tun0
resolvectl query --cache=no claude.ai           # -- link: wlan0
```

`Default Route: no` no tun0 é o que impede a VPN de virar o DNS de tudo.

---

## Voltar o MAC real do wifi

O wifi usa MAC estável por rede, não o de fábrica — é o que evita rastreamento
entre redes. Se alguma regra do roteador precisar do MAC real (reserva de
DHCP, filtro, controle parental):

```bash
nmcli connection modify "$WIFI" wifi.cloned-mac-address permanent
nmcli connection up "$WIFI"
```

E o caminho inverso:

```bash
nmcli connection modify "$WIFI" wifi.cloned-mac-address stable
```

Reserva de DHCP tem que ser criada **para o MAC em uso**, não para o de
fábrica — senão nasce morta. Veja o atual com:

```bash
ip link show wlan0 | awk '/link\/ether/{print $2}'
```

---

## `codex` reclamando de NVM

```
codex wrapper: NVM not found at ~/.nvm
```

Não deve mais acontecer: o wrapper procura outro `codex` no PATH e usa ele.
Se voltar, é porque só existe o wrapper:

```bash
type -a codex
npm install -g @openai/codex     # com o prefix do npm no $HOME
```
