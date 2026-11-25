#!/usr/bin/env bash
# Внутри образа, на копии репозитория в /tmp/curskill.
# Симлинки и файл хоста остаются в контейнере. Экран не поднимается.
set -euo pipefail

ROOT=/tmp/curskill
cd "$ROOT"
test "$(pwd)" = /tmp/curskill
test ! -d /data/pro/curskill

host=$(hostname)
test "$host" = curskill-test
envf="config/hosts/${host}.env"

echo "=== setup: пакеты на месте ==="
bash skill/scripts/setup.sh

echo "=== install.sh ==="
bash install/install.sh
test -L "$HOME/.cursor/skills/curskill"
test -L "$HOME/.claude/skills/curskill"
test "$(readlink -f "$HOME/.cursor/skills/curskill")" = "$ROOT/skill"
test "$(readlink -f "$HOME/.claude/skills/curskill")" = "$ROOT/skill"
test -f "$envf"
grep -q '^CURSKILL_SETUP_DONE=$' "$envf"
grep -q '^CURSOR_STAND_PROXY=$' "$envf"

refuse_click() {
  local out=$1
  if printf '%s\n' "$out" | grep -F 'стенд свободен — handoff --dry-run' >/dev/null; then
    echo "FAIL: doctor пошёл в dry-run" >&2
    exit 1
  fi
}

echo "=== doctor: настройка не закрыта ==="
set +e
out=$(timeout 45 bash skill/scripts/doctor.sh 2>&1)
code=$?
set -e
printf '%s\n' "$out"
test "$code" -ne 124
printf '%s\n' "$out" | grep -F 'handoff: настройка не закрыта' >/dev/null
printf '%s\n' "$out" | grep -F 'нет /usr/local/bin/cursor-proxy' >/dev/null
refuse_click "$out"

echo "=== doctor: флаг есть, экрана нет ==="
sed -i 's/^CURSKILL_SETUP_DONE=$/CURSKILL_SETUP_DONE=1/' "$envf"
sed -i 's/^CURSOR_STAND_X=$/CURSOR_STAND_X=xvfb/' "$envf"
grep -q '^CURSKILL_SETUP_DONE=1$' "$envf"
grep -q '^CURSOR_STAND_X=xvfb$' "$envf"
set +e
out=$(timeout 45 bash skill/scripts/doctor.sh 2>&1)
code=$?
set -e
printf '%s\n' "$out"
test "$code" -ne 124
printf '%s\n' "$out" | grep -F 'handoff: стенд не жив' >/dev/null
printf '%s\n' "$out" | grep -F 'CURSOR_STAND_X=xvfb' >/dev/null
refuse_click "$out"

if ps -C Xvfb >/dev/null 2>&1 || ps -C Xorg >/dev/null 2>&1; then
  echo "FAIL: тест поднял экран" >&2
  exit 1
fi

echo "fresh-install: ok"
