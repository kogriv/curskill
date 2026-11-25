#!/usr/bin/env bash
# sqlite/OCR сессий glass. Не печатает worker keys.
set -euo pipefail
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
PY="$(cursor_stand_resolve_glass)" || {
  echo "нет glass_agents.py" >&2
  exit 127
}
export CURSOR_STAND_PROFILE="${CURSOR_STAND_PROFILE:-${XDG_DATA_HOME:-$HOME/.local/share}/cursor-stand}"
exec python3 "$PY" "$@"
