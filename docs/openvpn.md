# OpenVPN client config (criptografado)

Este repo gerencia o config do cliente OpenVPN em `/etc/openvpn/client/client.conf` com criptografia **age** via chezmoi. O arquivo no repo é `etc/openvpn/client/encrypted_client.conf.age` e é descriptografado no apply.

## Configurar tudo (passo a passo)

Para parar de digitar usuário/senha toda vez que reinicia a VPN:

1. **Criar o arquivo de credenciais (uma vez)** — na raiz do repo:
   ```bash
   cd ~/Repos/dotfiles   # ou o path do seu clone
   sudo ./scripts/setup-openvpn-auth.sh
   ```
   O script pede usuário e senha, grava em `/etc/openvpn/client/auth.txt` (não vai pro Git) e ajusta permissões.

2. **Colocar no client.conf a linha que usa esse arquivo** — o target fica em `/etc`, então defina o destino como `/` (senão dá "not in destination directory" ou "not managed"):
   ```bash
   CHEZMOI_DESTINATION_DIR=/ chezmoi edit /etc/openvpn/client/client.conf
   ```
   Adicione uma linha (por exemplo no fim):
   ```ini
   auth-user-pass /etc/openvpn/client/auth.txt
   ```
   Salve e feche o editor.

3. **Aplicar no /etc usando o mesmo repo** — com `sudo` o chezmoi usa o home do root e não acha seu clone; é obrigatório passar o source:
   ```bash
   sudo chezmoi apply -S ~/Repos/dotfiles
   ```
   (Se der erro de path, use o path absoluto, ex.: `sudo chezmoi apply -S /home/rcamara/Repos/dotfiles`.)

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
3. No `client.conf` (use `CHEZMOI_DESTINATION_DIR=/` para o path `/etc/...` ser aceito):
   ```bash
   CHEZMOI_DESTINATION_DIR=/ chezmoi edit /etc/openvpn/client/client.conf
   ```
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

Edite com destino em `/` para o path `/etc/...` ser aceito (o chezmoi descriptografa para editar e recriptografa ao salvar):

```bash
CHEZMOI_DESTINATION_DIR=/ chezmoi edit /etc/openvpn/client/client.conf
```

Depois reaplique em `/etc` **passando o source** (senão o sudo usa o home do root e o apply não acha o repo) e reinicie a VPN:

```bash
sudo chezmoi apply -S ~/Repos/dotfiles
sudo systemctl restart openvpn-client@client
```

## Aplicar (deploy)

Na máquina onde quer o config (sempre com `-S` quando for aplicar em `/etc` com sudo):

```bash
sudo chezmoi apply -S ~/Repos/dotfiles
```

Isso grava o arquivo descriptografado em `/etc/openvpn/client/client.conf` com permissões (dir `750`, arquivo `640`, dono `root:network`) para o usuário `openvpn` (grupo `network`) conseguir ler.

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

Só o arquivo `.age` é versionado. Um `etc/openvpn/client/client.conf` em texto puro no source é ignorado pelo `.chezmoiignore`. Nunca faça commit do client config sem criptografia.
