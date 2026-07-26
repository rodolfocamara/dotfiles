#!/usr/bin/env bash
# Fecha o buraco do suspend com driver NVIDIA proprietário. Linux only.
#
# O pacote nvidia-utils já liga NVreg_PreserveVideoMemoryAllocations=1 em
# /usr/lib/modprobe.d/nvidia-sleep.conf. Isso manda o driver preservar a VRAM
# no suspend — mas quem de fato grava a VRAM em disco é o nvidia-suspend.service,
# que vem DESABILITADO. Resultado: o driver promete preservar e ninguém salva.
#
# O hook /usr/lib/systemd/system-sleep/nvidia não cobre isso. Fora do caso
# especial de suspend-then-hibernate ele trata só um gancho:
#
#     case "$1" in
#         post)  /usr/bin/nvidia-sleep.sh "resume" ;;
#     esac
#
# Só `post`. Não existe ramo `pre` — o lado do suspend fica descoberto.
#
# Em s2idle isso passa batido; em S3 (`deep`) a VRAM se perde de verdade e a
# volta vem preta ou corrompida. Ver docs/nvidia-displays.md.
#
#   ./scripts/setup-nvidia-sleep.sh              habilita
#   ./scripts/setup-nvidia-sleep.sh --dry-run    só mostra o que faria
#
# Idempotente: pode rodar de novo sem estragar nada.

set -euo pipefail

DRY=0
[[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && DRY=1

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
skip() { printf '  \033[33mpulado\033[0m  %s\n' "$*"; }
warn() { printf '  \033[33maviso\033[0m   %s\n' "$*"; }
ok()   { printf '  ok      %s\n' "$*"; }

# ── Pré-requisitos ───────────────────────────────────────────────
[[ "$(uname -s)" == "Linux" ]] || { echo "Linux only."; exit 1; }

if [[ $(id -u) -eq 0 ]]; then
  echo "Não rode com sudo. Rode como você mesmo — o script eleva onde precisa."
  exit 1
fi

command -v systemctl >/dev/null || { echo "systemd não encontrado."; exit 1; }

if [[ ! -d /sys/module/nvidia_drm ]]; then
  echo "Módulo nvidia_drm não está carregado — esta máquina não usa o driver"
  echo "proprietário da NVIDIA. Nada a fazer."
  exit 0
fi

if ! systemctl list-unit-files nvidia-suspend.service >/dev/null 2>&1; then
  echo "nvidia-suspend.service não existe. Instale nvidia-utils (ou o"
  echo "nvidia-<versão>xx-utils correspondente ao seu driver)."
  exit 1
fi

say "Estado atual"

# ── Diagnóstico: a opção que torna os serviços necessários ───────
# Sem PreserveVideoMemoryAllocations=1 os serviços ainda ajudam, mas o buraco
# é outro. Vale dizer qual dos dois mundos é o desta máquina.
if grep -rqs 'NVreg_PreserveVideoMemoryAllocations=1' \
     /etc/modprobe.d /usr/lib/modprobe.d 2>/dev/null; then
  ok "NVreg_PreserveVideoMemoryAllocations=1 configurado"
else
  warn "NVreg_PreserveVideoMemoryAllocations não está em 1 — os serviços abaixo"
  warn "ainda são o caminho certo, mas a preservação de VRAM não está ligada."
fi

# ── Diagnóstico: s2idle x deep ──────────────────────────────────
if [[ -r /sys/power/mem_sleep ]]; then
  MEM_SLEEP="$(cat /sys/power/mem_sleep)"
  if [[ "$MEM_SLEEP" == *"[deep]"* ]]; then
    ok "modo de suspend: deep (S3) — é aqui que a VRAM se perde"
  else
    ok "modo de suspend: $MEM_SLEEP"
  fi
fi

# ── Serviços ─────────────────────────────────────────────────────
# nvidia-hibernate fica de fora quando systemd-hibernate está mascarado:
#
#     [Install]
#     WantedBy=systemd-hibernate.service
#
# É o único WantedBy dele. Com o alvo apontando para /dev/null, habilitar é
# criar um link para um gancho que nunca dispara. nvidia-resume é outro caso:
# ele também pendura em systemd-suspend.service. A unit pode ficar habilitada
# mesmo se esse alvo estiver mascarado hoje, pronta para uma futura reativação.
UNITS=(nvidia-suspend.service nvidia-resume.service)

SUSPEND_STATE="$(systemctl is-enabled systemd-suspend.service 2>&1 || true)"
if [[ "$SUSPEND_STATE" == "masked" ]]; then
  SUSPEND_MASKED=1
  warn "systemd-suspend.service está mascarado — o PowerDevil só apaga a tela;"
  warn "as units NVIDIA não executam nesse wake. Ver fix-monitor-after-resume."
else
  SUSPEND_MASKED=0
fi

HIBER_STATE="$(systemctl is-enabled systemd-hibernate.service 2>&1 || true)"
if [[ "$HIBER_STATE" == "masked" ]]; then
  HIBER_MASKED=1
else
  HIBER_MASKED=0
  UNITS+=(nvidia-hibernate.service)
fi

say "Habilitando"

if [[ $HIBER_MASKED -eq 1 ]]; then
  skip "nvidia-hibernate.service — systemd-hibernate está mascarado aqui"
fi

TO_ENABLE=()
for u in "${UNITS[@]}"; do
  if [[ "$(systemctl is-enabled "$u" 2>&1)" == "enabled" ]]; then
    skip "$u — já habilitado"
  else
    TO_ENABLE+=("$u")
  fi
done

if [[ ${#TO_ENABLE[@]} -eq 0 ]]; then
  echo
  if [[ $SUSPEND_MASKED -eq 1 ]]; then
    echo "Nada a habilitar. As units estão prontas, mas dormentes enquanto"
    echo "systemd-suspend.service continuar mascarado."
  else
    echo "Nada a fazer — já está tudo no lugar."
  fi
  exit 0
fi

if [[ $DRY -eq 1 ]]; then
  printf '  sudo systemctl enable %s\n' "${TO_ENABLE[*]}"
  echo
  echo "(dry-run — nada foi alterado)"
  exit 0
fi

sudo systemctl enable "${TO_ENABLE[@]}"
for u in "${TO_ENABLE[@]}"; do ok "$u"; done

say "Pronto."
if [[ $SUSPEND_MASKED -eq 1 ]]; then
  echo "As units ficam prontas, mas só executarão se o suspend for desmascarado."
else
  echo "Vale no próximo suspend — não precisa reiniciar."
fi
