# Поля доктора без секретов. doctor.sh подключает этот файл.
# Функции ничего не печатают, кроме договорённых слов.

doctor_login_word() {
  local db=$1
  python3 - "$db" <<'PY'
import sqlite3
import sys

db = sys.argv[1]
try:
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    row = con.execute(
        "select value from ItemTable where key='cursorAuth/cachedEmail'"
    ).fetchone()
except Exception:
    print("нет")
    raise SystemExit(0)
if not row or row[0] in (None, "", b""):
    print("нет")
    raise SystemExit(0)
print("да")
PY
}

doctor_worker_count() {
  local profile=$1 n=0 pid cmd
  for pid in $(pgrep -f "worker start" 2>/dev/null || true); do
    [ -r "/proc/$pid/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *"$profile"/User/globalStorage/anysphere.cursor-agent-worker*) n=$((n + 1)) ;;
    esac
  done
  printf '%s\n' "$n"
}

# Печатает строки сверки версии. Код 0 — пакет и запись handoff совпали
# и калибровка (мажор.минор) совпала с пакетом. Иначе код 1, строки на stdout.
doctor_anchor_lines() {
  local pkg=$1 checked=$2 calibrated=$3 mm bad=0
  mm=$(printf '%s\n' "$pkg" | awk -F. '{print $1"."$2}')
  if [ -n "$calibrated" ] && [ -n "$mm" ] && [ "$calibrated" != "$mm" ]; then
    printf 'якоря калиброваны на %s, пакет %s\n' "$calibrated" "$pkg"
    bad=1
  fi
  if [ -z "$checked" ]; then
    printf 'handoff эту версию не записывал\n'
    bad=1
  elif [ -n "$pkg" ] && [ "$checked" != "$pkg" ]; then
    printf 'Cursor обновлён до %s, handoff не проверен (ui-checked %s)\n' "$pkg" "$checked"
    bad=1
  elif [ -n "$pkg" ] && [ "$checked" = "$pkg" ]; then
    printf 'якоря проверены для %s\n' "$pkg"
  fi
  return "$bad"
}
