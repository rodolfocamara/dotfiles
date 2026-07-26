# Tela externa acende, o KDE marca "connected/enabled", e mesmo assim não vem
# imagem. É o nvidia_drm perdendo a corrida do modeset no hotplug: ele recebe o
# HPD e lê o EDID, mas nunca completa o link training. Trocar de modo e voltar
# força um modeset novo e o link engata.
#
# Diagnóstico rápido de que é esse o caso (e não cabo ou entrada errada):
# `ddcutil detect` acha o monitor pelo EDID mas `ddcutil --bus N getvcp D6`
# falha. A EEPROM do EDID vive dos +5V do cabo e responde com o monitor
# apagado; o DDC/CI só responde com o scaler acordado. Ver docs/nvidia-displays.md.
#
#   fix-monitor              cicla toda tela externa ligada
#   fix-monitor HDMI-A-1     cicla só essa
#   fix-monitor --top        cicla a tela externa mais acima no layout
#   fix-monitor --dry-run    só mostra os comandos que rodaria

function fix-monitor --description 'Força um modeset nas telas externas (NVIDIA + KDE)'
    argparse 'n/dry-run' 't/top' -- $argv
    or return 1

    if set -q _flag_top; and test (count $argv) -gt 0
        echo "fix-monitor: --top não aceita um output junto." >&2
        return 1
    end

    if not command -q kscreen-doctor
        echo "fix-monitor: kscreen-doctor não encontrado — isto é KDE only." >&2
        return 1
    end
    if not command -q jq
        echo "fix-monitor: jq não encontrado (sudo pacman -S jq)." >&2
        return 1
    end

    set -l json (kscreen-doctor --json 2>/dev/null | string collect)
    if test -z "$json"
        echo "fix-monitor: kscreen-doctor não respondeu. Tem sessão KDE ativa?" >&2
        return 1
    end

    # Sem argumento, pega toda tela externa ligada. O painel do notebook fica
    # de fora de propósito: o bug é do link externo, e piscar o painel só
    # atrapalha (é nele que você está lendo o erro, se der errado).
    set -l targets
    if set -q _flag_top
        # Automatiza o caso desta máquina sem amarrar o comando ao nome do
        # conector: cabo/driver podem trocar HDMI-A-1 por outro nome. Em empate,
        # mantém a primeira saída devolvida pelo KScreen.
        set targets (echo $json | jq -r '
            [.outputs[]
             | select(.enabled and .connected)
             | select(.name | test("^(eDP|LVDS|DSI)") | not)]
            | if length > 0 then min_by(.pos.y).name else empty end')
    else if test (count $argv) -gt 0
        set targets $argv
    else
        set targets (echo $json | jq -r '
            .outputs[]
            | select(.enabled and .connected)
            | select(.name | test("^(eDP|LVDS|DSI)") | not)
            | .name')
    end

    if test (count $targets) -eq 0
        echo "fix-monitor: nenhuma tela externa ligada." >&2
        return 1
    end

    set -l failed 0
    for out in $targets
        set -l cur (echo $json | jq -r --arg n "$out" '
            .outputs[] | select(.name==$n) | .currentModeId')

        if test -z "$cur" -o "$cur" = null
            echo "fix-monitor: $out não existe ou está desligado." >&2
            set failed 1
            continue
        end

        set -l curname (echo $json | jq -r --arg n "$out" '
            .outputs[] | select(.name==$n)
            | .currentModeId as $c
            | .modes[] | select(.id==$c) | .name')

        # O modo intermediário só precisa ser diferente do atual — quanto menor,
        # menos banda, mais chance de fechar o link numa placa que está confusa.
        set -l low (echo $json | jq -r --arg n "$out" '
            .outputs[] | select(.name==$n)
            | .currentModeId as $c
            | [.modes[] | select(.id != $c)]
            | sort_by(.size.width * .size.height)
            | .[0].id')

        set -l lowname (echo $json | jq -r --arg n "$out" --arg l "$low" '
            .outputs[] | select(.name==$n) | .modes[] | select(.id==$l) | .name')

        if test -z "$low" -o "$low" = null
            echo "fix-monitor: $out só tem um modo, nada a ciclar." >&2
            set failed 1
            continue
        end

        echo "$out: $curname → $lowname → $curname"

        if set -q _flag_dry_run
            echo "  kscreen-doctor output.$out.mode.$low"
            echo "  kscreen-doctor output.$out.mode.$cur"
            continue
        end

        if not kscreen-doctor output.$out.mode.$low >/dev/null 2>&1
            echo "fix-monitor: $out não aceitou o modo $lowname." >&2
            set failed 1
            continue
        end

        sleep 2

        # A volta é a parte que importa. Se ela falhar a tela fica num modo
        # ruim mas visível, então o erro é alto e diz como desfazer na mão.
        if not kscreen-doctor output.$out.mode.$cur >/dev/null 2>&1
            echo "fix-monitor: $out ficou em $lowname — não voltou para $curname." >&2
            echo "  desfaça com: kscreen-doctor output.$out.mode.$cur" >&2
            set failed 1
        end
    end

    return $failed
end
