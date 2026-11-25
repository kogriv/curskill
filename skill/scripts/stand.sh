#!/usr/bin/env bash
# Резолвит канонический cursor-stand.sh и exec. Копии скрипта в skill нет (B-165).
set -euo pipefail
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
SH="$(cursor_stand_resolve_sh)" || {
  echo "cursor-stand.sh не найден. Задай CURSOR_STAND_SH= или клонируй curskill." >&2
  exit 127
}
exec "$SH" "$@"
