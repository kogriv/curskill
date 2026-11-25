#!/usr/bin/env bash
# Поведение BL-047…BL-066 без Xorg, без кликов и без секретов в stdout.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
sh="$root/automation/cursor-stand.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

extract() {
  awk -v fn="$1" '
    $0 ~ ("^" fn "\\(\\)") {p=1}
    p {print}
    p && /^}/ {exit}
  ' "$sh"
}

# --- BL-047: тег и каталог runtime, Xorg не стартует ---
xorg="$root/automation/curskill-xorg"
set +e
"$xorg" paths :105 '../etc' >"$tmp/bad.out" 2>"$tmp/bad.err"
rc=$?
set -e
[ "$rc" = 2 ]
[ ! -s "$tmp/bad.out" ]
set +e
"$xorg" start :105 'a/b' >"$tmp/bad2.out" 2>"$tmp/bad2.err"
rc=$?
set -e
[ "$rc" = 2 ]
mkdir -p "$tmp/run"
CURSKILL_XORG_RUNTIME="$tmp/run" "$xorg" paths :105 cursor-stand >"$tmp/paths"
[ "$(wc -l <"$tmp/paths")" = 3 ]
while IFS= read -r line; do
  case "$line" in
    "$tmp/run"/*) ;;
    *) echo "путь runtime вне каталога теста" >&2; exit 1 ;;
  esac
  case "$line" in
    /tmp/curskill-xorg-nvidia-headless.conf|/tmp/xorg-empty-confdir|/tmp/xorg-*.log)
      echo "путь остался в предсказуемом /tmp" >&2
      exit 1
      ;;
  esac
done <"$tmp/paths"
grep -q -- '-nolisten tcp' "$xorg"

# --- BL-052: пустой прокси запускает бинарь без --proxy-server ---
cat >"$tmp/fake-cursor" <<'EOF'
#!/bin/sh
printf '%s\n' "$@"
EOF
chmod +x "$tmp/fake-cursor"
out=$(CURSOR_STAND_PROXY= CURSOR_STAND_CONFIG=/dev/null \
  CURSOR_STAND_CURSOR_BIN="$tmp/fake-cursor" \
  "$root/automation/cursor-proxy" --version)
printf '%s\n' "$out" | grep -q -- '--version'
if printf '%s\n' "$out" | grep -q -- '--proxy-server'; then
  echo "пустой прокси всё ещё передаёт --proxy-server" >&2
  exit 1
fi
out=$(CURSOR_STAND_PROXY='http://user:alpha@127.0.0.1:9' \
  CURSOR_STAND_CURSOR_BIN="$tmp/fake-cursor" \
  "$root/automation/cursor-proxy")
printf '%s\n' "$out" | grep -q -- '--proxy-server='

# --- BL-053: doctor не печатает URL ---
set +e
dout=$(CURSOR_STAND_CONFIG=/dev/null CURSOR_STAND_PROXY='http://user:s3cret-proxy@127.0.0.1:1' \
  "$root/skill/scripts/doctor.sh" 2>&1)
set -e
if printf '%s\n' "$dout" | grep -q 's3cret-proxy'; then
  echo "doctor напечатал URL прокси" >&2
  exit 1
fi
printf '%s\n' "$dout" | grep -q 'порт 1'

# --- BL-061: userinfo не срезает хост; мёртвый локальный порт — отказ ---
eval "$(extract proxy_host)"
eval "$(extract proxy_port)"
eval "$(extract port_busy)"
eval "$(extract require_local_proxy_port)"
[ "$(proxy_host 'http://user:pass@127.0.0.1:10816')" = "127.0.0.1" ]
[ "$(proxy_port 'http://user:pass@127.0.0.1:10816')" = "10816" ]
if require_local_proxy_port 'http://user:pass@127.0.0.1:1'; then
  echo "мёртвый порт 1 не отказал" >&2
  exit 1
fi
require_local_proxy_port 'http://user:pass@example.invalid:9'

# --- BL-048 BL-049: лог без URL, нет DevTools, значения в кавычках ---
eval "$(extract write_xdg_open)"
BIN="$tmp/bin"
VAR="$tmp/var"
DISP=:105
PROFILE="$tmp/profile"
CURSOR_PROXY=/usr/local/bin/cursor-proxy
PROXY_HTTP='http://user:s3cret pass@127.0.0.1:9'
mkdir -p "$BIN" "$VAR" "$PROFILE"
write_xdg_open
if grep -q 'remote-debugging' "$BIN/xdg-open"; then
  echo "в xdg-open остался DevTools" >&2
  exit 1
fi
if grep -q 'xdg-open \$\*' "$BIN/xdg-open"; then
  echo "лог xdg-open пишет аргументы" >&2
  exit 1
fi
grep -q 'echo "$(date -Iseconds) xdg-open"' "$BIN/xdg-open"
if grep -q 's3cret pass@' "$BIN/xdg-open"; then
  echo "прокси в xdg-open без кавычек" >&2
  exit 1
fi
grep -q 's3cret\\ pass@' "$BIN/xdg-open"

# --- BL-055: файл пароля 0600, значение наружу не печатается ---
eval "$(extract ensure_vnc_pass)"
VAR="$tmp/vnc"
mkdir -p "$VAR"
ensure_vnc_pass >/dev/null
[ "$(stat -c %a "$VAR/vnc.pass")" = 600 ]
[ -s "$VAR/vnc.pass" ]

# --- BL-056: чужой ключ в argv не глотается и не печатается ---
snip=$(sed -n '/^SANITIZED_ARGS=()/,/^unset SANITIZED_ARGS$/p' \
  "$root/automation/cursor-agent-argv-sanitize.sh")
run_snip() {
  # $1 — уже заданный ключ или пусто, дальше аргументы лаунчера
  env -u CURSOR_API_KEY bash -c '
    if [ -n "$1" ]; then export CURSOR_API_KEY="$1"; fi
    shift
    '"$snip"'
    printf "argc=%s\n" "$#"
    printf "flag=%s\n" "$(printf "%s\n" "$@" | grep -c -- "--api-key" || true)"
    if [ -n "${CURSOR_API_KEY:-}" ]; then printf "key=set\n"; else printf "key=empty\n"; fi
  ' bash "$@"
}
out=$(run_snip '' --api-key alpha --worker-dir /tmp/x)
printf '%s\n' "$out" | grep -q 'flag=0'
printf '%s\n' "$out" | grep -q 'key=set'
if printf '%s\n' "$out" | grep -q 'alpha'; then
  echo "сниппет напечатал ключ" >&2
  exit 1
fi
set +e
err=$(run_snip alpha --api-key beta --worker-dir /tmp/x 2>&1)
rc=$?
set -e
[ "$rc" != 0 ]
if printf '%s\n' "$err" | grep -q 'alpha\|beta'; then
  echo "отказ лаунчера напечатал ключ" >&2
  exit 1
fi
printf '%s\n' "$err" | grep -q 'не совпадает'
# Уже пропатченный лаунчер со старым блоком получает отказ на расхождении.
eval "$(extract sanitize_cursor_agent_launchers)"
HERE="$root/automation"
PROFILE="$tmp/prof"
ver="$PROFILE/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions/1"
mkdir -p "$ver"
cat >"$ver/cursor-agent" <<'EOF'
#!/bin/sh
# cursor-stand argv-sanitize: --api-key -> CURSOR_API_KEY
SANITIZED_ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --api-key)
      if [ "$#" -ge 2 ]; then
        if [ -z "${CURSOR_API_KEY:-}" ]; then
          export CURSOR_API_KEY="$2"
        fi
        shift 2
      fi
      ;;
    *) SANITIZED_ARGS+=("$1"); shift ;;
  esac
done
set -- "${SANITIZED_ARGS[@]}"
unset SANITIZED_ARGS
should_skip_system_ca() {
  return 0
}
EOF
sanitize_cursor_agent_launchers
grep -q 'не совпадает с --api-key' "$ver/cursor-agent"

# --- BL-057: пустой список отказывает до клика; занятая сессия в cmd_archive раньше ---
eval "$(extract archive_protection_ok)"
ARCHIVE_PROTECTED_IDS=
ARCHIVE_PROTECTED_NAMES=
set +e
archive_protection_ok bc-1 name >"$tmp/archive.err" 2>&1
rc=$?
set -e
[ "$rc" != 0 ]
grep -q 'список защиты пуст' "$tmp/archive.err"
ARCHIVE_PROTECTED_IDS=bc-keep
if archive_protection_ok bc-keep n >/dev/null; then
  echo "защищённый id прошёл" >&2
  exit 1
fi
archive_protection_ok bc-other n
awk '
  /^cmd_archive\(\)/ {p=1}
  p && /status=1/ {seen=1}
  p && seen && /archive_protection_ok/ {ok=1; exit}
  p && /^}/ {exit}
  END {exit !ok}
' "$sh"

# --- BL-052: нет окна — up_require отказывает ---
eval "$(extract up_require_agents_window)"
open_agents_window_if_needed() { return 1; }
agents_window() { return 0; }
DISP=:105
VAR="$tmp"
if up_require_agents_window; then
  echo "нет окна, а up_require вернул 0" >&2
  exit 1
fi
open_agents_window_if_needed() { return 0; }
agents_window() { echo 99; }
up_require_agents_window >/dev/null

# --- BL-060: занятый снимок не даёт сигнал ---
eval "$(extract ensure_idle_now)"
GLASS_AGENTS="$tmp/busy-stub.py"
cat >"$GLASS_AGENTS" <<'EOF'
import sys
sys.stdout.write("bc-1\tworking\t/tmp\tlocal-rc\t1\n")
EOF
: >"$tmp/shot"
if ensure_idle_now "$tmp/shot" k-99 >/dev/null; then
  echo "busy не остановил ensure" >&2
  exit 1
fi
cat >"$GLASS_AGENTS" <<'EOF'
raise SystemExit(0)
EOF
ensure_idle_now "$tmp/shot" k-99

# --- BL-063: «отправлен» только внутри ok=1 ---
awk '
  /^cmd_handoff\(\)/ {p=1}
  p && /if \[ "\$ok" -eq 1 \]; then/ {branch=1}
  p && branch && /handoff отправлен/ {sent=1}
  p && branch && /^  else$/ {if (sent) good=1}
  p && /^}/ {exit}
  END {exit !good}
' "$sh"

# --- BL-065: заглушки больше нет ---
if grep -n 'handoff_ui_ok' "$sh"; then
  echo "handoff_ui_ok ещё в скрипте" >&2
  exit 1
fi

# --- BL-066: этот файл гоняет поведение, старый цикл 5 с по-прежнему запрещён ---
if grep -n 'for i in 1 2 3 4 5 6 7 8 9 10; do' "$sh"; then
  echo "старый опрос 5 с ещё в скрипте" >&2
  exit 1
fi

echo "audit fixes ok"
