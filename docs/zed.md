# Zed com cara de VSCode / Claude Desktop

Objetivo: parar de perder músculo trocando de editor. O Zed vira "VSCode com
painel de agente à direita", igual nas duas máquinas (Arch e Windows).

## Arquivos

```
.chezmoitemplates/zed/settings.json     <- fonte da verdade (conteúdo único)
.chezmoitemplates/zed/keymap.json       <- idem

dot_config/zed/settings.json.tmpl       --> ~/.config/zed/settings.json      (Linux/macOS)
dot_config/zed/keymap.json.tmpl         --> ~/.config/zed/keymap.json
AppData/Roaming/Zed/settings.json.tmpl  --> %APPDATA%\Zed\settings.json      (Windows)
AppData/Roaming/Zed/keymap.json.tmpl    --> %APPDATA%\Zed\keymap.json
```

Os quatro alvos são wrappers de uma linha (`{{ template "zed/settings.json" . }}`).
O Zed no Windows lê `%APPDATA%\Zed\`, não `~/.config/zed/` — daí a árvore
`AppData/`. `.chezmoiignore` corta `AppData/` fora do Windows e `.config/zed/`
dentro dele.

## Editar

**Edite `.chezmoitemplates/zed/`, nunca o alvo.** Como o alvo é template,
`chezmoi re-add ~/.config/zed/settings.json` **não** funciona aqui (ele
sobrescreveria o wrapper pelo JSON renderizado).

```bash
vim ~/Repos/dotfiles/.chezmoitemplates/zed/settings.json
cma   # chezmoi apply
```

Cuidado: mexer em preferência pela UI do Zed (`ctrl-,`) escreve direto no alvo
e o `chezmoi status` passa a acusar diff. Quando isso acontecer, copie a chave
nova para o template e reaplique.

## O que foi mudado (e o que já vinha de graça)

O keymap default do Zed no Linux **já é praticamente o do VSCode**. Vem de
fábrica, não precisa de config: `ctrl-p`, `ctrl-shift-p`, `ctrl-t`, `ctrl-b`,
`ctrl-alt-b`, `ctrl-j`, ``ctrl-` ``, `ctrl-shift-e/f/g/x/m/o`, `ctrl-w`,
`ctrl-k w`, `ctrl-k ctrl-w`, `alt-1..9`, `ctrl-tab`, `f2`, `f8`, `f12`,
`ctrl-.`, `ctrl-h`, `ctrl-shift-h`, `ctrl-r`, `alt-up/down`, `ctrl-shift-k`,
`ctrl-/`, `ctrl-d`, `ctrl-shift-l`, `ctrl-\`, `ctrl-k ctrl-0`, `ctrl-k ctrl-j`.

O que a config faz de fato:

| Área | Antes (default do Zed) | Depois |
|---|---|---|
| `base_keymap` | `"Zed"` | `"VSCode"` — soma `shift-alt-f`, `ctrl-i`, `ctrl-k z`, `f5/f10/f11`, `ctrl-alt-i` |
| Explorer / Outline / Git | dock à **direita** | à **esquerda**, como o VSCode |
| Painel de agente | dock à **esquerda** | à **direita**, 560px — onde o Copilot Chat mora |
| Minimap | desligado | `"auto"`, thumb no hover |
| Abas | sem ícone, sem cor de git | ícone de arquivo, cor de git status, marca erro |
| Indent guides | cor fixa | `indent_aware` |
| Barra de menu | escondida | visível no título |
| Format on save | `"off"` | `"on"` |
| Copiar linha | `ctrl-alt-shift-up/down` | `shift-alt-up/down` (VSCode) |
| Inserir cursor acima/abaixo | `shift-alt-up/down` | `ctrl-alt-up/down` (VSCode) |
| Fonte do agente | 12px | 14px |

O "jeitão Claude Desktop" do painel de agente **já é default no Zed 1.12**:
largura de leitura limitada e centralizada (`limit_content_width` +
`max_content_width: 850`), histórico de threads na lateral (`sidebar_side`),
Enter envia (`use_modifier_to_send: false`), cards de edit e de terminal
expandidos. Só o dock e a largura precisaram mudar.

## Pegadinhas

- **`format_on_save: "on"`** roda o LSP/prettier do projeto. Em repo sem
  formatter configurado pode gerar diff largo. Para desligar num projeto só:
  `"format_on_save": "off"` no `.zed/settings.json` do repo.
- **Autosave** fica `"off"` (igual VSCode). Se ligar `"on_focus_change"`,
  lembre que no Zed o autosave **dispara o format_on_save**.
- **Fontes**: o terminal do Zed usa `JetBrainsMono Nerd Font Mono`, a mesma
  família do `dot_config/kitty/kitty.conf`. Ela não vem por padrão: instale com
  `sudo pacman -S ttf-jetbrains-mono-nerd` ou baixando o `JetBrainsMono.tar.xz`
  do [nerd-fonts](https://github.com/ryanoasis/nerd-fonts/releases) para
  `~/.local/share/fonts/` + `fc-cache -f`. Sem ela o starship perde os glyphs.
- **`ctrl-alt-up/down`** também é scroll do output no painel de agente
  (contexto `AcpThread`). O binding daqui é escopado em `Editor && mode == full`
  justamente para não roubar isso.
- **Ícones estilo VSCode**: o `icon_theme` é `Catppuccin Mocha` (extensão). Se
  quiser o visual Seti do VSCode, instale a extensão `vscode-icons` e troque
  `icon_theme`.

## Voltar atrás

O backup do settings anterior ficou em
`~/.config/zed/settings.json.bak-pre-vscode-profile`.
