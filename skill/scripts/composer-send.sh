#!/usr/bin/env bash
# Resend в поле ввода открытой вкладки glass (после worker-not-ready). Не New Chat.
# Только через cursor-stand.sh composer-send: поле ввода ищется по снимку, с --id
# проверяется открытая вкладка. Своего клика по фиксированной точке здесь нет —
# 960,545 в переписке попадает в ленту, текст уходит мимо (07.10.2026).
#   composer-send.sh [--id bc-…] [--dry-run] [текст]
set -euo pipefail
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SH="$(cursor_stand_resolve_sh 2>/dev/null)" || { echo "cursor-stand.sh не найден" >&2; exit 127; }
cursor_stand_has_cmd "$SH" composer-send || {
  echo "в $SH нет composer-send — обнови скрипт стенда; вслепую не кликаю" >&2
  exit 1
}
exec "$SH" composer-send "$@"
