# Perfil por máquina

## O problema

O chezmoi separa alvos por SO. Só que SO não é granularidade suficiente aqui:
as duas máquinas Linux deste repo rodam desktops diferentes — uma Hyprland,
outra KDE Plasma. O `dot_config/hypr`, `waybar` e `wofi` são corretos numa e
lixo na outra.

Sem separação isso não dá erro, dá algo pior: `chezmoi status` lista 20 alvos
que nunca vão ser aplicados naquela máquina. Aí você para de ler o status, e
quando aparece um alvo pendente **de verdade** ele some no meio do ruído.

Medida antes/depois numa máquina KDE:

```
antes:   47 alvos pendentes (A)
depois:  23 alvos pendentes (A)
```

Os 23 que sobraram são reais — `.local/bin`, direnv, zsh, os alvos de `/etc`.

## Como definir

Na raiz do source (`~/Repos/dotfiles/.chezmoidata.toml`). O arquivo é por
máquina e **não vai pro git** — já está no `.gitignore`:

```toml
profile = "hyprland"    # ou "kde", ou "generic"
```

Só `"hyprland"` tem significado hoje; qualquer outro valor cai no mesmo
comportamento (corta o stack de desktop). Os nomes existem para o arquivo ser
legível daqui a seis meses.

## Sem o arquivo

Detecta sozinho, pelo binário do compositor:

```
{{ $profile := (index . "profile") | default (ternary "hyprland" "generic" (ne (lookPath "Hyprland") "")) }}
```

Máquina com Hyprland instalado recebe o stack; o resto não. Ou seja: numa
máquina nova você não *precisa* criar o `.chezmoidata.toml` — ele existe para
quando você quiser contrariar a detecção (por exemplo, preparar os configs do
Hyprland numa máquina onde ele ainda não foi instalado).

## O que o perfil corta

| Alvo | Regra |
|---|---|
| `.config/hypr/`, `.config/waybar/`, `.config/wofi/`, `.config/kitty/` | só no perfil `hyprland` |
| `.wslconfig` | só no Windows — quem lê é o host, em `%USERPROFILE%\.wslconfig` |
| `etc/wsl.conf` | só dentro do WSL |

O gate de `$profile` também pega o Windows (lá ele resolve para `generic`),
por isso essas quatro linhas saíram do bloco `{{ if eq .chezmoi.os "windows" }}`
— estavam duplicando a mesma decisão em dois lugares.

## Verificar

```bash
# qual perfil esta máquina resolveu
chezmoi execute-template '{{ index . "profile" | default "(detectado)" }}'

# o que está sendo cortado
chezmoi ignored | sort

# quantos alvos pendentes sobraram
chezmoi status | grep -c '^ A'
```

## Próximo knob óbvio

`.gitconfig-work` e `.claude-work/settings.json` são de máquina de trabalho e
hoje aparecem pendentes em qualquer máquina. Um `work = true` no mesmo
`.chezmoidata.toml` resolveria igual. Não foi feito aqui porque depende de
decidir o que é a máquina de trabalho — o mecanismo já está no lugar.
