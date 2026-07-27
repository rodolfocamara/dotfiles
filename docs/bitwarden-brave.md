# Bitwarden desktop ↔ extensão no Brave

Destravar a extensão do Bitwarden com o app desktop (biometria ou "unlock with
desktop") depende de Native Messaging: a extensão chama
`connectNative("com.8bit.bitwarden")`, o navegador procura um manifest com esse
nome no diretório `NativeMessagingHosts/` **dele**, e o manifest aponta pro
`desktop_proxy` que conversa com o app.

## Assinatura da falha

A extensão pede a senha mestra toda vez, mesmo com o app desktop aberto e
destravado. Na tela de biometria a opção some ou fica cinza. Nada disso é
problema de conta, de sincronização ou de configuração da extensão.

O diretório do Brave é que está vazio:

```bash
ls ~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/
ls ~/.config/google-chrome/NativeMessagingHosts/
```

Se `com.8bit.bitwarden.json` aparece no do Chrome mas não no do Brave, é isso.

## Por que acontece

O app desktop escreve o manifest sozinho quando "Integração com navegador" está
ligada — mas só nos navegadores que ele conhece. No Linux, `getLinuxNMHS()` em
`/usr/lib/bitwarden/app.asar` retorna exatamente quatro:

```js
Firefox:          ~/.mozilla/
Chrome:           ~/.config/google-chrome/
Chromium:         ~/.config/chromium/
"Microsoft Edge": ~/.config/microsoft-edge/
```

Brave não está na lista (no macOS a lista é maior e inclui Vivaldi, Zen e
Helium). E navegador Chromium não lê o `NativeMessagingHosts/` de outro
navegador — cada um só olha o próprio perfil. Então o manifest nunca chega lá.

Conferido na versão 2026.3.1 do pacote `bitwarden`. Vale para instalação
nativa, flatpak ou snap: o que muda é o caminho do proxy, não a lista.

## O que o repo faz

`run_onchange_after_60-bridge-bitwarden-brave.sh.tmpl` copia o manifest que o
próprio Bitwarden escreveu (Chrome, Chromium ou Edge, o primeiro que existir)
para o diretório do Brave, e apaga o `com.bitwarden.desktop.json` legado, que é
o nome antigo do host e hoje só serve pro Firefox.

Copiar em vez de versionar um JSON pronto é intencional. O manifest carrega dois
valores que não são estáveis:

- `path` — `/usr/lib/bitwarden/desktop_proxy` na instalação por pacote, outro
  caminho em flatpak;
- `allowed_origins` — a lista de IDs de extensão do Bitwarden, que muda quando
  eles publicam builds novas.

Derivando do arquivo de origem, os dois acompanham o upgrade sozinhos. O hash
no topo do script é o do manifest de origem, então um update do Bitwarden que
mude o conteúdo faz o script rodar de novo no próximo `chezmoi apply`.

## O outro lado: o app precisa estar rodando

O manifest só resolve o transporte. Quem destrava é o processo do desktop, e ele
escreve o socket em `~/.cache/com.bitwarden.desktop/s.bw` enquanto está vivo:

```bash
pgrep -af bitwarden-desktop
ls ~/.cache/com.bitwarden.desktop/
```

Diretório vazio = app fechado = extensão vai pedir a senha mestra, com manifest
ou sem. Para o app sobreviver ao fechar a janela, ligue no desktop:

- Configurações → Aparência → **Minimizar/fechar para a bandeja**
- Configurações → **Iniciar automaticamente ao fazer login**

E na extensão do Brave, Configurações → Segurança → **Desbloquear com
biometria** (ela só aparece depois que o manifest existe e o app está aberto).

## Verificação

```bash
# manifest no lugar certo, apontando pro proxy do pacote
cat ~/.config/BraveSoftware/Brave-Browser/NativeMessagingHosts/com.8bit.bitwarden.json

# a extensão instalada bate com algum allowed_origins acima
ls ~/.config/BraveSoftware/Brave-Browser/Default/Extensions/nngceckbapebfimnlniiiahkandclblb

# o app registrou o servidor de Native Messaging
grep "Native messaging server started" ~/.config/Bitwarden/app.log | tail -1
```

Depois de instalar o manifest, reinicie o Brave por inteiro. Recarregar a
extensão não basta: a lista de hosts de Native Messaging é lida na inicialização
do navegador.
