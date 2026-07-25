# OpenVPN

Existem **dois caminhos** neste repo, e eles não se misturam. Escolha pela máquina:

| Máquina | Caminho | Onde está |
|---|---|---|
| Arch/KDE (desktop) | **NetworkManager** (plasma-nm) | [`scripts/setup-vpn-nm.sh`](../scripts/setup-vpn-nm.sh) — ver [VPN pelo NetworkManager](#vpn-pelo-networkmanager) |
| WSL / servidor sem desktop | `openvpn-client@` do systemd | `etc/openvpn/` + [`scripts/install-etc.sh`](../scripts/install-etc.sh) — o resto deste documento |

Se você já usa a VPN no plasma-nm, **não** precisa de nada de `/etc`: o NetworkManager tem o próprio cliente, o próprio split-DNS e não lê o `client.conf`.

---

## VPN pelo NetworkManager

Importar um `.ovpn` cru no plasma-nm dá um perfil que **sequestra a rota default e o DNS inteiro** — o resto da internet para de funcionar e o resolver da empresa passa a ver todo domínio que você consulta. O script corrige isso:

```bash
./scripts/setup-vpn-nm.sh --dry-run
./scripts/setup-vpn-nm.sh
```

O que ele garante no perfil:

| Ajuste | Por quê |
|---|---|
| `ipv4/ipv6.never-default yes` | a VPN não vira rota default; só as sub-redes que o servidor empurrar passam por ela |
| `ipv4/ipv6.dns-search ~dominio` | só esses domínios vão pro DNS da VPN (o `~` = domínio de roteamento) |
| `ipv4/ipv6.dns-priority 50` | positivo, então o link nunca vira rota default de DNS |
| `connection.mdns 0` / `llmnr 0` | não anuncia o nome da sua máquina dentro da rede remota |

Nada específico da empresa está no repo — **este repositório é público**. Endpoint, domínios internos e usuário ficam no `.chezmoidata.toml` (por máquina, no `.gitignore`), e o `.ovpn` fica fora do repo:

```toml
[workVpn]
ovpnFile        = "~/Documents/vpn/EMPRESA.ovpn"
splitDnsDomains = ["empresa.com.br", "empresa.local"]
username        = "seu.usuario"
```

Conferir depois de conectar:

```bash
ip route get 1.1.1.1                            # tem que sair pela interface normal
resolvectl status tun0                          # Default Route: no
resolvectl query --cache=no <dominio-interno>   # tem que responder por tun0
```

**Para subir sozinho no boot**, a senha precisa estar guardada no sistema, não na KWallet: no diálogo de senha marque "armazenar para todos os usuários" (isso muda `password-flags` de `1` para `0`). Com a senha *agent-owned* o NM só consegue autenticar depois que você loga na sessão gráfica.

---

## VPN pelo systemd (WSL / sem desktop)

Este repo versiona o config do cliente OpenVPN em `/etc/openvpn/client/client.conf` com criptografia **age**. O arquivo no repo é `etc/openvpn/client/encrypted_client.conf.age`.

> **Mudou:** a árvore `etc/` **não passa mais pelo chezmoi**. Quem instala é `scripts/install-etc.sh`. Ver [Por que /etc saiu do chezmoi](#por-que-etc-saiu-do-chezmoi) no fim.

## Configurar tudo (passo a passo)

Para parar de digitar usuário/senha toda vez que reinicia a VPN:

1. **Criar o arquivo de credenciais (uma vez)** — na raiz do repo:
   ```bash
   cd ~/Repos/dotfiles   # ou o path do seu clone
   sudo ./scripts/setup-openvpn-auth.sh
   ```
   O script pede usuário e senha, grava em `/etc/openvpn/client/auth.txt` (não vai pro Git) e ajusta permissões.

2. **Colocar no client.conf a linha que usa esse arquivo.** O arquivo no repo é criptografado, então edite descriptografando e recriptografando na raiz do repo:
   ```bash
   cd ~/Repos/dotfiles
   chezmoi decrypt etc/openvpn/client/encrypted_client.conf.age > /tmp/client.conf
   $EDITOR /tmp/client.conf
   ```
   Adicione uma linha (por exemplo no fim):
   ```ini
   auth-user-pass /etc/openvpn/client/auth.txt
   ```
   Recriptografe e apague o texto claro:
   ```bash
   age -e -r "$(age-keygen -y < ~/.config/chezmoi/age.txt)" \
       < /tmp/client.conf > etc/openvpn/client/encrypted_client.conf.age
   shred -u /tmp/client.conf
   ```

3. **Instalar em /etc:**
   ```bash
   ./scripts/install-etc.sh --dry-run   # confere os caminhos primeiro
   ./scripts/install-etc.sh
   ```
   Rode como você mesmo, **não** com `sudo` — o script eleva sozinho onde precisa. Com `sudo`, o chezmoi olharia para o home do root e não acharia nem seus dados nem a chave age.

4. **Reiniciar a VPN:**
   ```bash
   sudo systemctl restart openvpn-client@client
   ```
   A partir daí não deve mais pedir usuário/senha no terminal.

## Criptografia (age)

- **Identity** (descriptografar): `~/.config/chezmoi/age.txt` — você já tem.
- **Recipient** (criptografar): necessário para `chezmoi add --encrypt`. Obtenha com:
  ```bash
  age-keygen -y < ~/.config/chezmoi/age.txt
  ```
  Coloque essa linha como `recipient = "age1..."` em `[age]` no `~/.config/chezmoi/chezmoi.toml` para poder adicionar ou recriptografar arquivos.

O chezmoi descriptografa automaticamente ao rodar `apply`, `diff` ou `edit`; não precisa descriptografar à mão.

## Primeira vez: adicionar o config ao repo

Com `sudo`, o chezmoi usa `/root` como destino, então `chezmoi add /etc/...` falha. Crie o arquivo criptografado manualmente a partir da **raiz do repo** (como seu usuário normal):

1. Tenha o recipient do age no config (veja [Criptografia](#criptografia-age)); obtenha com `age-keygen -y < ~/.config/chezmoi/age.txt`.
2. Crie o arquivo criptografado na **raiz do repo de dotfiles** (sudo só para ler o config; o redirect roda como você, então o arquivo fica no repo):
   ```bash
   cd ~/Repos/dotfiles   # ou seu path real do repo
   sudo cat /etc/openvpn/client/client.conf | age -e -r "$(age-keygen -y < ~/.config/chezmoi/age.txt)" > etc/openvpn/client/encrypted_client.conf.age
   ```
3. Faça commit do novo arquivo criptografado:
   ```bash
   git add etc/openvpn/client/encrypted_client.conf.age
   git commit -m "Add encrypted OpenVPN client.conf"
   ```

## Usuário e senha (auth-user-pass)

O servidor pode pedir usuário e senha. Você precisa de um **arquivo de credenciais** (ou script) que o OpenVPN lê. **Não coloque esse arquivo no repo** — senha em texto aberto no Git é risco de segurança.

**Arquivo recomendado:** `/etc/openvpn/client/auth.txt`

1. Crie o arquivo (uma vez por máquina):
   ```bash
   sudo touch /etc/openvpn/client/auth.txt
   sudo chmod 600 /etc/openvpn/client/auth.txt
   sudo chown root:root /etc/openvpn/client/auth.txt
   ```
2. Conteúdo: **duas linhas** — primeira linha = usuário, segunda linha = senha:
   ```bash
   sudo nano /etc/openvpn/client/auth.txt
   ```
   Exemplo:
   ```
   seu_usuario
   sua_senha
   ```
3. No `client.conf` (ver [Atualizar o config](#atualizar-o-config) para o ciclo de descriptografar/editar/recriptografar):
   Adicione **com o caminho do arquivo**:
   ```ini
   auth-user-pass /etc/openvpn/client/auth.txt
   ```
   **Importante:** tem que ser `auth-user-pass /caminho/para/auth.txt`. Se estiver só `auth-user-pass` (sem path), o OpenVPN pede usuário/senha no terminal. Para conferir depois do apply: `sudo grep auth-user-pass /etc/openvpn/client/client.conf`.
4. O diretório `/etc/openvpn/client/` já é `750` e o `client.conf` é `640`; o `auth.txt` com `600` só o root lê. O processo OpenVPN (que roda como usuário `openvpn`) precisa conseguir ler o arquivo: ou o grupo do arquivo é `network` e a permissão do diretório permite, ou você deixa `640` e dono `root:network` (o mesmo do client.conf) para o openvpn ler. No Arch, o serviço `openvpn-client@client` costuma rodar como root, então `600` com dono root basta.

**Faz sentido ter um arquivo assim “aberto”?** Não. Por isso:
- **Não** versionar `auth.txt` no Git.
- Deixar o arquivo em `/etc` com permissão restrita (`600` ou `640`, dono root).
- Em cada máquina nova, criar o `auth.txt` à mão (ou com um script local que não vai pro repo).

## Atualizar o config

O `chezmoi edit` não serve aqui: o alvo não é do chezmoi. O ciclo é descriptografar num temporário, editar e recriptografar por cima do arquivo do repo:

```bash
cd ~/Repos/dotfiles
chezmoi decrypt etc/openvpn/client/encrypted_client.conf.age > /tmp/client.conf
$EDITOR /tmp/client.conf
age -e -r "$(age-keygen -y < ~/.config/chezmoi/age.txt)" \
    < /tmp/client.conf > etc/openvpn/client/encrypted_client.conf.age
shred -u /tmp/client.conf
```

Depois instale e reinicie:

```bash
./scripts/install-etc.sh
sudo systemctl restart openvpn-client@client
```

## Aplicar (deploy)

```bash
./scripts/install-etc.sh --dry-run   # mostra os caminhos, não escreve nada
./scripts/install-etc.sh
```

Rode **como você mesmo**, não com `sudo`: o script eleva sozinho nos `install`, mas a renderização do template e a descriptografia precisam rodar com o seu usuário (é onde estão o `.chezmoidata.toml` e a chave age).

O script grava o `client.conf` descriptografado em `/etc/openvpn/client/client.conf` com dir `750`, arquivo `640` e dono `root:network`, para o usuário `openvpn` (grupo `network`) conseguir ler. Se a chave age não existir na máquina, ele pula esse arquivo e instala o resto.

## Reiniciar a VPN

Depois de mudar o config:

```bash
sudo systemctl restart openvpn-client@client
```

## Verificar DNS (systemd-resolved)

Com a VPN ligada e os scripts dns-up/dns-down em uso:

```bash
resolvectl status tun0
```

Você deve ver os servidores DNS da VPN e os domínios split-DNS do túnel.

## Sem plaintext no repo

Só o arquivo `.age` é versionado. A árvore `etc/` inteira é ignorada pelo `.chezmoiignore`, então um `client.conf` em texto puro no source nunca vira alvo. Ainda assim: nunca faça commit do client config sem criptografia.

## Por que /etc saiu do chezmoi

Gerenciar arquivo fora do `$HOME` é um [non-goal declarado](https://github.com/twpayne/chezmoi/discussions/1510) do chezmoi. O `destDir` dele é sempre o home, e a árvore `etc/` do source mapeava para dentro dele:

```
$ chezmoi target-path etc/openvpn/scripts/executable_dns-up.sh.tmpl
/home/rcamara/etc/openvpn/scripts/dns-up.sh      # não /etc/...
```

Três coisas que a documentação antiga mandava fazer e que **não funcionavam**:

| Comando | O que acontecia de verdade |
|---|---|
| `CHEZMOI_DESTINATION_DIR=/ chezmoi edit ...` | essa variável não existe no chezmoi; era ignorada em silêncio |
| `sudo chezmoi apply -S ~/Repos/dotfiles` | com sudo o `$HOME` vira `/root`, então o destino virava `/root/etc/...` |
| blocos `[ "etc/..." ] target = "/etc/..."` no config | formato não suportado no chezmoi v2 — no-op (o comentário no próprio arquivo já admitia isso) |

Existe um `--destination /` que faz o `etc/` mapear certo, mas aí **todo o resto do repo passa a mirar a raiz do sistema** (`dot_zshrc` → `/.zshrc`, `dot_config/starship.toml` → `/.config/starship.toml`). Um `sudo chezmoi apply --destination /` sem argumentos de path espalharia seus dotfiles na raiz. Não vale o risco por quatro arquivos.

Daí o `scripts/install-etc.sh`: renderiza o template e descriptografa como você, e chama `sudo install` só na hora de escrever.
