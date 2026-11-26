#!/bin/bash
# BL-080…BL-083: каталог команд совпадает со скриптом, живые тексты не ждут BL-067.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
en="$root/skill/capabilities.md"
ru="$root/skill/capabilities.ru.md"
sh="$root/automation/cursor-stand.sh"
skill="$root/skill/SKILL.md"
skillru="$root/skill/SKILL.ru.md"
road="$root/skill/docs/roadmap/README.md"

[ -f "$en" ] && [ -f "$ru" ]

cmds=$(grep -E '^  [a-z0-9-]+\) cmd_' "$sh" | sed -E 's/^  ([a-z0-9-]+)\).*/\1/')
[ -n "$cmds" ]
for cmd in $cmds; do
  grep -qx "### $cmd" "$en"
  grep -qx "### $cmd" "$ru"
done

for sub in list find enable disable add ready; do
  grep -qx "#### $sub" "$en"
  grep -qx "#### $sub" "$ru"
done

glass=$(grep -oE 'scripts/glass\.sh [a-z-]+' "$skill" | awk '{print $2}' | sort -u)
[ -n "$glass" ]
for cmd in $glass; do
  grep -qx "### $cmd" "$en"
  grep -qx "### $cmd" "$ru"
done

header=$(sed -n '1,60p' "$sh")
printf '%s\n' "$header" | grep -q 'mcp ready'
printf '%s\n' "$header" | grep -q 'INVENTORY.md' && {
  echo "шапка скрипта всё ещё ссылается на INVENTORY.md" >&2
  exit 1
}

for f in "$skill" "$skillru"; do
  desc=$(sed -n '1,20p' "$f")
  printf '%s\n' "$desc" | grep -q 'enabling project MCP' && {
    echo "description всё ещё называет проектный MCP путём до вкладки: $f" >&2
    exit 1
  }
  printf '%s\n' "$desc" | grep -q 'On Cursor 3.23' && {
    echo "description всё ещё привязывает handoff только к 3.23: $f" >&2
    exit 1
  }
  grep -q 'capabilities' "$f"
done

for f in "$skill" "$skillru" "$road"; do
  grep -q 'пока замер не записан' "$f" && { echo "живой текст ждёт замер: $f" >&2; exit 1; }
  grep -q 'Пока замера нет' "$f" && { echo "живой текст ждёт замер: $f" >&2; exit 1; }
  grep -q 'Сначала BL-067' "$f" && { echo "живой текст начинает с BL-067: $f" >&2; exit 1; }
  grep -q 'until it is written down' "$f" && { echo "living text still waits on BL-067: $f" >&2; exit 1; }
done

grep -q 'skill/capabilities.ru.md' "$root/README.ru.md"
grep -q 'Описание возможностей' "$root/README.ru.md"
grep -q 'skill/capabilities.md' "$root/README.md"
grep -q 'agent worker start' "$skill"
grep -q 'agent worker start' "$skillru"
grep -q 'agent worker start' "$road"
grep -q '3\.30\.14' "$root/skill/reference.md"
grep -q '3\.30\.14' "$root/skill/reference.ru.md"
grep -q 'CURSOR_STAND_UI_CALIBRATED' "$skill"
grep -A1 'CURSOR_STAND_UI_CALIBRATED' "$skill" | grep -q '3\.23'

echo "capabilities checks ok"
