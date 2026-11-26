#!/bin/bash
# Приёмка BL-072 и BL-073 на подставных значениях. Живой стенд не кликает.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck source=../../skill/scripts/doctor_contract.sh
. "$root/skill/scripts/doctor_contract.sh"

out=$(doctor_anchor_lines "3.30.14" "3.30.14" "3.30")
printf '%s\n' "$out" | grep -qx 'якоря проверены для 3.30.14'

set +e
out=$(doctor_anchor_lines "3.30.14" "3.30.14" "3.23")
rc=$?
set -e
[ "$rc" = 1 ]
printf '%s\n' "$out" | grep -qx 'якоря калиброваны на 3.23, пакет 3.30.14'

set +e
out=$(doctor_anchor_lines "3.30.14" "3.23.1" "3.30")
rc=$?
set -e
[ "$rc" = 1 ]
printf '%s\n' "$out" | grep -F 'handoff не проверен' >/dev/null

db=$(mktemp)
python3 - "$db" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table ItemTable (key text, value text)")
con.execute("insert into ItemTable values ('cursorAuth/cachedEmail', 'person@example.com')")
con.commit()
PY
word=$(doctor_login_word "$db")
[ "$word" = "да" ]
# Адрес в вывод не попадает.
doctor_login_word "$db" | grep -q '@' && { echo "doctor_login_word напечатал адрес" >&2; exit 1; }
rm -f "$db"

empty=$(mktemp)
python3 - "$empty" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("create table ItemTable (key text, value text)")
con.commit()
PY
[ "$(doctor_login_word "$empty")" = "нет" ]
rm -f "$empty"

# Опись ворот есть в обоих reference.
for f in "$root/skill/reference.md" "$root/skill/reference.ru.md"; do
  grep -q 'Planning next moves' "$f"
  grep -q 'composer-send' "$f"
  grep -q 'куда смотреть' "$f" || grep -q 'where to look' "$f"
done

echo "roadmap checks ok"
