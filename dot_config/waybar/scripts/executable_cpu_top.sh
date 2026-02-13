#!/usr/bin/env bash
# CPU: ícone + valor; classe muda com uso (low/mid/high/crit)
cpu=$(awk '/^cpu /{u=$2+$4; t=$2+$3+$4+$5+$6+$7+$8} END{printf "%.0f", u*100/t}' /proc/stat)
if   (( cpu < 40 )); then cls="low"
elif (( cpu < 70 )); then cls="mid"
elif (( cpu < 90 )); then cls="high"
else                       cls="crit"
fi
top10=$(ps axo pid,%cpu,comm --sort=-%cpu | head -11 | tail -10 | awk '{printf "%5s %5s%% %s\\n", $1, $2, $3}')
echo "{\"text\": \"\uf2db\\n${cpu}%\", \"tooltip\": \"Top CPU:\\n${top10}\", \"class\": \"${cls}\"}"
