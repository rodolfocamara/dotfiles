# artifacts/ — material sensível fora do git

**Este repositório é público** (`github.com/rodolfocamara/dotfiles`). Nada que
identifique infraestrutura interna pode ser commitado: certificado de CA
corporativa, kubeconfig, IP de cluster, chave de API.

Mas parte desse material é justamente o que falta para uma máquina nova ficar
pronta. `artifacts/` resolve o meio-termo: mora dentro do repo, à mão dos
scripts, e nunca sai daqui.

    artifacts/          # ignorado pelo git E pelo chezmoi
    ├── ca/             # certificados de CA interna
    ├── kube/           # kubeconfigs
    └── etc/            # recortes de /etc específicos da máquina (fstab…)

## Por que dois arquivos de ignore

O `.gitignore` esconde do git. Ele **não** esconde do chezmoi — o destDir do
chezmoi é sempre o home, então uma pasta na raiz do source vira alvo em `~`. Sem
a entrada correspondente no `.chezmoiignore`, um `chezmoi apply` criaria
`~/artifacts/` com uma cópia de tudo. É a mesma razão de `etc/` estar lá; ver
`scripts/install-etc.sh`.

Se você adicionar um subdiretório novo aqui, não precisa mexer em nada: os dois
ignores pegam a árvore inteira.

## O que NÃO fazer

- **`git add -f artifacts/...`** — o `-f` existe exatamente para furar o
  `.gitignore`. Não há proteção depois disso; o commit vai para um repo público.
- **Tratar como backup.** A pasta não é replicada em lugar nenhum. Se a máquina
  morrer, morre junto. O que precisa sobreviver vai para o gerenciador de
  segredos, não para cá.
- **Guardar o que já é derivável.** Kubeconfig gerado por `terraform output` ou
  `microk8s config` se refaz sozinho; guardar uma cópia velha só cria dúvida
  sobre qual é a boa.

## Alternativa quando precisa sobreviver

Para segredo que precisa ir junto para outra máquina, o repo já tem criptografia
com age — ver `etc/openvpn/client/encrypted_client.conf.age` e o trecho
correspondente de `scripts/install-etc.sh`. Isso pode ser commitado; `artifacts/`
é para o que não vale o esforço ou não pode sair da máquina.
