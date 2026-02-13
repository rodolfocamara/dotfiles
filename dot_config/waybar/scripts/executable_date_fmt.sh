#!/usr/bin/env bash
# Data formatada: dia e mês (3 letras uppercase) centralizados
day=$(date '+%d')
mon=$(date '+%b' | tr '[:lower:]' '[:upper:]')
tooltip=$(date '+%A, %d %B %Y')
# Pad dia com espaço para igualar largura do mês (3 chars)
printf '{"text": " %s\\n%s", "tooltip": "%s"}\n' "$day" "$mon" "$tooltip"
