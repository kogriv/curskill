#!/usr/bin/env bash
# Ждать private worker стенда для папки. Cmdline не печатать (там ключ).
set -euo pipefail
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

[ $# -ge 1 ] || { echo "usage: wait-worker.sh /abs/project [timeout_sec]" >&2; exit 1; }
WS=$(readlink -f -- "$1") || exit 1
[ -d "$WS" ] || { echo "нет каталога $1" >&2; exit 1; }
TIMEOUT="${2:-${CURSOR_STAND_WAIT_WORKER_SEC:-120}}"
PROFILE="$(cursor_stand_profile)"
MARKER="$PROFILE/User/globalStorage/anysphere.cursor-agent-worker"

if SH="$(cursor_stand_resolve_sh 2>/dev/null)" && cursor_stand_has_cmd "$SH" wait-worker; then
  exec "$SH" wait-worker "$WS"
fi

worker_dirs() {
  local pid cmd
  for pid in $(pgrep -f "worker start" 2>/dev/null || true); do
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *"$MARKER"*) ;;
      *) continue ;;
    esac
    tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null \
      | awk 'p { print; exit } $0 == "--worker-dir" { p = 1 }'
  done | sort -u
}

i=0
while [ "$i" -lt "$TIMEOUT" ]; do
  i=$((i + 1))
  if worker_dirs | grep -qxF "$WS"; then
    echo "воркер есть  $WS  (${i}s)"
    exit 0
  fi
  sleep 1
done
echo "wait-worker: за ${TIMEOUT}s нет воркера $WS" >&2
exit 1
