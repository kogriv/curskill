#!/usr/bin/env bash
# Показать, какой X-сервер выбрал бы стенд (не поднимает экран).
set -euo pipefail
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if SH="$(cursor_stand_resolve_sh 2>/dev/null)" && cursor_stand_has_cmd "$SH" pick-display; then
  exec "$SH" pick-display
fi

DISP_SH="$(cursor_stand_resolve_display_sh)" || {
  echo "нет stand-display.sh" >&2
  exit 127
}
echo "display_sh  $DISP_SH"
echo "CURSOR_STAND_X  ${CURSOR_STAND_X:-auto}"
# shellcheck disable=SC1090
. "$DISP_SH"
echo -n "pick  "
stand_pick_xserver
DISP="${CURSOR_STAND_DISPLAY:-:105}"
if xdpyinfo -display "$DISP" >/dev/null 2>&1; then
  num="${DISP#:}"
  pid=$(tr -d ' \n' < "/tmp/.X${num}-lock" 2>/dev/null || true)
  cmd=$(ps -o args= -p "${pid:-0}" 2>/dev/null | tr -s ' ' | cut -c1-100)
  echo "live  $DISP  pid=${pid:-?}  $cmd"
else
  echo "live  $DISP  нет"
fi
