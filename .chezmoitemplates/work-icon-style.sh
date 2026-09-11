# shellcheck shell=bash
# Esta paleta distingue o ambiente de trabalho sem depender do tema de ícones.
# Os pontos ficam visíveis em tamanhos médios; em 16–24 px, cor e maleta ainda
# preservam a leitura rápida na barra de tarefas.
WORK_ICON_NAVY='#1C386B'
WORK_ICON_CYAN='#0AA8E3'
WORK_ICON_DOT='#74D4F4'
WORK_ICON_ACCENT='#97CA3D'

work_icon_make_master() {
    local source_icon=$1
    local output_file=$2
    local scratch_dir=$3
    local style=${4:-profile}
    local normalized_icon=$scratch_dir/normalized.png
    local blue_icon=$scratch_dir/blue.png
    local dot_mask=$scratch_dir/dot-mask.png
    local dots=$scratch_dir/dots.png
    local dots_alpha=$scratch_dir/dots-alpha.png
    local dots_intersection=$scratch_dir/dots-intersection.png
    local clipped_dots=$scratch_dir/clipped-dots.png
    local dotted_icon=$scratch_dir/dotted.png
    local badge=$scratch_dir/badge.png

    mkdir -p "$scratch_dir"
    # A densidade alta evita serrilhado quando a origem é um SVG de tema.
    magick -background none -density 384 "$source_icon" -resize 256x256 -gravity center \
        -extent 256x256 PNG32:"$normalized_icon"

    # Trocar só a matiz mantém áreas brancas, sombras e o desenho original.
    magick "$normalized_icon" -colorspace HSL -channel R \
        -evaluate set 57.5% +channel -colorspace sRGB \
        -modulate 92,112,100 PNG32:"$blue_icon"

    case "$style" in
        profile)
            # Nos ícones de perfil, os pontos pertencem somente à área colorida.
            magick "$normalized_icon" -colorspace HSL -channel G -separate \
                -threshold 18% "$dot_mask"
            ;;
        application)
            # Apps monocromáticos também precisam mostrar o marcador pontilhado.
            magick "$normalized_icon" -alpha extract "$dot_mask"
            magick "$blue_icon" -fuzz 12% -fill "$WORK_ICON_NAVY" \
                -opaque '#111111' PNG32:"$scratch_dir/application-blue.png"
            mv "$scratch_dir/application-blue.png" "$blue_icon"
            ;;
        *)
            echo "work-icon-style: estilo inválido: $style" >&2
            return 2
            ;;
    esac

    magick -size 256x256 xc:none \
        -fill "$WORK_ICON_DOT" \
        -draw 'circle 36,48 42,48 circle 54,35 60,35 circle 56,57 64,57 circle 75,44 82,44 circle 78,66 84,66 circle 96,54 102,54 circle 46,78 51,78 circle 65,85 72,85 circle 87,83 92,83 circle 103,74 108,74' \
        -fill "$WORK_ICON_ACCENT" -draw 'circle 33,67 39,67' \
        PNG32:"$dots"
    magick "$dots" -alpha extract "$dots_alpha"
    magick "$dots_alpha" "$dot_mask" -compose Multiply -composite \
        "$dots_intersection"
    magick "$dots" "$dots_intersection" -alpha off -compose CopyOpacity \
        -composite PNG32:"$clipped_dots"
    magick "$blue_icon" "$clipped_dots" -compose over -composite \
        PNG32:"$dotted_icon"

    magick -size 104x104 xc:none \
        -fill "$WORK_ICON_NAVY" -stroke "$WORK_ICON_CYAN" -strokewidth 5 \
        -draw 'circle 52,52 52,5' \
        -fill none -stroke '#ffffff' -strokewidth 8 \
        -draw 'roundrectangle 36,25 68,46 5,5' \
        -fill '#ffffff' -stroke none \
        -draw 'roundrectangle 20,38 84,78 7,7' \
        -fill "$WORK_ICON_NAVY" -draw 'rectangle 20,53 84,59' \
        -fill '#ffffff' -draw 'roundrectangle 47,50 57,63 2,2' \
        PNG32:"$badge"
    magick "$dotted_icon" "$badge" -gravity southeast -geometry +2+2 \
        -composite PNG32:"$output_file"
}

work_icon_render_sizes() {
    local master=$1
    local icon_name=$2
    local icons_dir=$3
    local dry_run=$4
    local size target_dir target_file temporary_file

    for size in 16 24 32 48 64 128 256; do
        target_dir=$icons_dir/${size}x${size}/apps
        target_file=$target_dir/$icon_name.png

        if $dry_run; then
            printf 'DRY-RUN: geraria %s\n' "$target_file"
            continue
        fi

        mkdir -p "$target_dir"
        temporary_file=$(mktemp "$target_dir/.$icon_name.XXXXXX")
        magick "$master" -resize "${size}x${size}" -strip \
            -define png:exclude-chunks=date,time PNG32:"$temporary_file"

        if [[ ! -f "$target_file" ]] || ! cmp -s "$temporary_file" "$target_file"; then
            install -m 0644 "$temporary_file" "$target_file"
            WORK_ICON_GENERATED=$((WORK_ICON_GENERATED + 1))
        fi
        rm -f "$temporary_file"
    done
}
