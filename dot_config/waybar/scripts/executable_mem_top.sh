#!/usr/bin/env bash
# Memória: ícone + usado/total em 2 linhas; classe muda com uso (low/mid/high/crit)
read used total < <(free -g | awk '/Mem:/{print $3, $2}')
pct=0
[[ $total -gt 0 ]] && pct=$(( used * 100 / total ))
if   (( pct < 40 )); then cls="low"
elif (( pct < 70 )); then cls="mid"
elif (( pct < 90 )); then cls="high"
else                       cls="crit"
fi
top10=$(ps axo pid,%mem,comm --sort=-%mem | head -11 | tail -10 | awk '{printf "%5s %5s%% %s\\n", $1, $2, $3}')
echo "{\"text\": \"\uf538\\n${used}G\\n${total}G\", \"tooltip\": \"${pct}% usado\\n\\nTop Mem:\\n${top10}\", \"class\": \"${cls}\"}"
