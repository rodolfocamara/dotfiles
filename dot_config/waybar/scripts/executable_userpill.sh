#!/usr/bin/env bash
# Mostra 2 iniciais do user num "pill" circular
# Se o user tiver 1 palavra: primeiras 2 letras; se tiver 2+: iniciais
name="$USER"
if [[ "$name" == *" "* ]]; then
  first="${name%% *}"
  last="${name##* }"
  initials="${first:0:1}${last:0:1}"
else
  initials="${name:0:2}"
fi
initials="${initials^^}"
host=$(cat /etc/hostname 2>/dev/null || uname -n 2>/dev/null || echo "localhost")
echo "{\"text\": \"${initials}\", \"tooltip\": \"${USER}@${host}\", \"class\": \"userpill\"}"
