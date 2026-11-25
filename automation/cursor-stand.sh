#!/usr/bin/env bash
# Стенд Cursor Agents Window на отдельном GPU-дисплее.
#
# Зачем. Штатного тула «новый агент + /remote-control» нет. CLI/Cloud —
# другие сессии. Computer-use по столу владельца (:1) крадёт фокус.
# Эталон 19.09.2026: свой DISPLAY, --user-data-dir, cursor-proxy, не копия
# живого ~/.config/Cursor. Замер: INVENTORY.md, волны 2–4.
#
# Экран: CURSOR_STAND_DISPLAY_SH, иначе $HERE/display/stand-display.sh.
# Останавливать Xorg только по PID своего дисплея, никогда pkill Xorg.
#
#   cursor-stand.sh status
#   cursor-stand.sh up
#   cursor-stand.sh workers       # поднять воркеры папок этой машины (открыть их вкладки)
#   cursor-stand.sh ensure        # up, если стенд не целый, + workers (таймер cursor-stand.timer)
#   cursor-stand.sh shot
#   cursor-stand.sh handoff -w /path/to/project -n name --then 'Reply with only the word PONG.'
#   cursor-stand.sh handoff --dry-run -w /path/to/project   # шаги 1–5, без Return и без конвертации RC
#   cursor-stand.sh handoff --trace -w /path/to/project     # как dry-run, но текст вставляется; первая новая сессия — Stop и archive
#   cursor-stand.sh handoff /path/to/project '…'    # папка первым аргументом, если это каталог
#   cursor-stand.sh handoff -w /ABS --no-convert       # локальный чат без RC (проба / recover)
#   cursor-stand.sh convert --id <uuid|bc-…|имя> [-n имя] [--dry-run]
#   cursor-stand.sh rename --id bc-… новое-имя
#   cursor-stand.sh rename --from 'Pong response output' pong
#   cursor-stand.sh rename --current pong
#   cursor-stand.sh focus --id bc-…   # открыть вкладку сессии
#   cursor-stand.sh archive --id bc-… # сайдбар → Archive (не выполняющуюся)
#   cursor-stand.sh mcp list                     # Customize → MCPs, список серверов
#   cursor-stand.sh mcp find NAME                # есть ли NAME (код 0/1 + status)
#   cursor-stand.sh mcp enable NAME              # тоггл источника ON (проектный/user)
#   cursor-stand.sh mcp disable NAME             # тоггл OFF
#   cursor-stand.sh mcp add -w /ABS -n NAME --command /path [--arg …]
#   cursor-stand.sh mcp add --user -n NAME --command /path   # ~/.cursor/mcp.json
#   cursor-stand.sh settings agents              # Settings → Agents, только чтение
#   cursor-stand.sh wait-worker /path/to/project   # ждать private worker папки (не печатать cmdline)
#   cursor-stand.sh composer-send              # Return в композер текущей вкладки (resend)
#   cursor-stand.sh pick-display               # auto|xorg|xvfb — что выбрал бы stand_pick_xserver
#   cursor-stand.sh park          # Cursor стенда; экран и VNC остаются
#   cursor-stand.sh down          # park + x11vnc
#   cursor-stand.sh down-display  # и экран тоже — ТОЛЬКО :105
#
# handoff без папки не запускать: convert на Home/No Repo падает (волна 4).
# Один стенд :105, только этот хост. Новые агенты — вкладки, не новые Xorg.
#
# Журнал и state — $CURSOR_STAND_PROFILE/var (вне git). Секреты сюда не писать.
# Handoff 3.23: короткое первое сообщение → конвертация футера → задача
# (--then / --then-file). Слэш /remote-control не использовать.
# Оверлеи: toast expensive-processes (крестик), диалог Move agent… (Cancel).

set -euo pipefail

# --locked ставит только повторный запуск из-под flock ниже.
# Переменная окружения для этого не годится: её наследует Cursor и воркер,
# и следующий cursor-stand.sh из той же сессии шёл бы мимо замка.
locked=0
if [ "${1:-}" = "--locked" ]; then
  locked=1
  shift
fi
CMD="${1:-status}"
shift || true

HERE="$(cd "$(dirname "$0")" && pwd)"
# Профиль машины: CURSOR_STAND_CONFIG или ../config/hosts/<hostname>.env
# (файл в gitignore; образец — *.env.example). Без него дефолты переносимые,
# не чужая машина.
_cursor_stand_cfg="${CURSOR_STAND_CONFIG:-$HERE/../config/hosts/$(hostname).env}"
if [ -f "$_cursor_stand_cfg" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$_cursor_stand_cfg"
  set +a
fi
unset CURSOR_STAND_LOCKED

PROFILE="${CURSOR_STAND_PROFILE:-${XDG_DATA_HOME:-$HOME/.local/share}/cursor-stand}"
export CURSOR_STAND_PROFILE="$PROFILE"
# Мажор.минор, с которым сняты якоря cmd_handoff (не патч-релиз). Справка, не запрет.
UI_CALIBRATED="${CURSOR_STAND_UI_CALIBRATED:-3.23}"
# Имя и isArchived в cloudAgentRepository отстают от клика.
# 25.11.2026 k-99: 5 с давали ложный отказ, запись приходила без второго клика
# (rename cur-mql и curskill-e2e, archive curskill-e2e). Потолок 60 с,
# выход сразу, как sqlite совпал.
SQLITE_UI_WAIT_SEC="${CURSOR_STAND_SQLITE_UI_WAIT_SEC:-60}"
# handoff папку берёт только явным -w. Пустой дефолт — папка не подставляется.
WORKSPACE_ENV="${CURSOR_STAND_WORKSPACE:-}"
WORKSPACE="${WORKSPACE_ENV:-}"
DISP="${CURSOR_STAND_DISPLAY:-:105}"
VNC_PORT="${CURSOR_STAND_VNC:-5916}"
# Пусто = без прокси. Порт фермы задаёт config/hosts/<host>.env.
PROXY_HTTP="${CURSOR_STAND_PROXY:-}"
CURSOR_PROXY="${CURSOR_STAND_BIN:-/usr/local/bin/cursor-proxy}"
LIVE_LOCK="${CURSOR_LIVE_LOCK:-$HOME/.config/Cursor/code.lock}"
VAR="$PROFILE/var"
STATE="$VAR/state.env"
# park/down ставят метку: таймер (ensure) не поднимает остановленный вручную стенд; up её снимает.
HOLD="$VAR/hold"
BIN="$PROFILE/bin"
# Стол владельца. Не брать $DISPLAY агента/worker'а: статус
# тогда мерил мышь стенда и писал «:1», хотя стол не трогали.
ORIG_DISPLAY="${CURSOR_STAND_ORIG_DISPLAY:-:1}"
GLASS_AGENTS="${CURSOR_STAND_GLASS_AGENTS:-$HERE/glass_agents.py}"
if [ -n "${CURSOR_STAND_DISPLAY_SH:-}" ]; then
  STAND_DISPLAY_SH="$CURSOR_STAND_DISPLAY_SH"
else
  STAND_DISPLAY_SH="$HERE/display/stand-display.sh"
fi

# shellcheck disable=SC1090
. "$STAND_DISPLAY_SH"

port_busy() { ss -ltn 2>/dev/null | grep -q ":${1} "; }

mouse1() {
  DISPLAY="${ORIG_DISPLAY}" xdotool getmouselocation 2>/dev/null || echo unavailable
}

# PID'ы главного процесса Cursor стенда. Не матчить chrome-login, gpu/renderer
# и эту оболочку. Если нет cursor-bin, wrapper запускает /usr/share/cursor/cursor.
stand_cursor_pids() {
  local pid cmd
  for pid in $(pgrep -f "user-data-dir=$PROFILE" 2>/dev/null || true); do
    [ "$pid" = "$$" ] && continue
    [ "$pid" = "$PPID" ] && continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *chrome-login*) continue ;;
      *--type=*) continue ;;
      *cursor-bin*--user-data-dir="$PROFILE"*) echo "$pid" ;;
      *cursor-proxy*--user-data-dir="$PROFILE"*) echo "$pid" ;;
      */usr/share/cursor/cursor*--user-data-dir="$PROFILE"*) echo "$pid" ;;
    esac
  done
}

# Worker, поднятый ИЗ профиля стенда. Живой ~/.config/Cursor — не трогать:
# у него тот же сокет, что у этой сессии (волна 4).
stand_worker_pids() {
  local pid cmd
  for pid in $(pgrep -f "worker start" 2>/dev/null || true); do
    [ -r "/proc/$pid/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *"$PROFILE"/User/globalStorage/anysphere.cursor-agent-worker*) echo "$pid" ;;
    esac
  done
}

live_cursor_pid() {
  local p
  [ -f "$LIVE_LOCK" ] || { echo ""; return 0; }
  p=$(tr -d ' \n' < "$LIVE_LOCK" 2>/dev/null || true)
  case "$p" in ''|*[!0-9]*) echo ""; return 0 ;; esac
  # замок остаётся после падения (oomd 05.10.2026) — живой только существующий cursor
  if kill -0 "$p" 2>/dev/null && tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q cursor; then
    echo "$p"
  else
    echo ""
  fi
}

proc_env() {
  local pid=$1 key=$2
  tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
    | sed -n "s/^${key}=//p" | head -1 || true
}

# Шина живого Cursor стенда, не dbus этой агент-сессии.
dbus_addr_alive() {
  local a=$1 path
  [ -n "$a" ] || return 1
  case "$a" in
    unix:path=*)
      path=${a#unix:path=}
      path=${path%%,*}
      [ -S "$path" ] || [ -e "$path" ]
      ;;
    *) return 0 ;;
  esac
}

stand_dbus() {
  local pid addr
  pid=$(stand_cursor_pids | head -1)
  if [ -n "$pid" ]; then
    addr=$(proc_env "$pid" DBUS_SESSION_BUS_ADDRESS)
    dbus_addr_alive "$addr" && { echo "$addr"; return 0; }
  fi
  if [ -f "$STATE" ]; then
    addr=$(sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' "$STATE" | head -1 || true)
    dbus_addr_alive "$addr" && { echo "$addr"; return 0; }
  fi
  if [ -f /tmp/cursor-stand-wave3/state.txt ]; then
    addr=$(sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' /tmp/cursor-stand-wave3/state.txt | head -1 || true)
    dbus_addr_alive "$addr" && { echo "$addr"; return 0; }
  fi
  return 1
}

kill_pids() {
  local pid
  for pid in "$@"; do
    [ -n "$pid" ] || continue
    { [ "$pid" = "$$" ] || [ "$pid" = "$PPID" ]; } && continue
    if [ -n "$(live_cursor_pid)" ] && [ "$pid" = "$(live_cursor_pid)" ]; then
      echo "Отказ: PID $pid — живой Cursor стола ($LIVE_LOCK). Не трогаю." >&2
      exit 1
    fi
    kill -TERM "$pid" 2>/dev/null || true
  done
}

write_xdg_open() {
  mkdir -p "$BIN"
  local chrome=""
  if [ -x /opt/google/chrome/chrome ]; then
    chrome=/opt/google/chrome/chrome
  elif command -v google-chrome >/dev/null 2>&1; then
    chrome=$(command -v google-chrome)
  elif command -v chromium >/dev/null 2>&1; then
    chrome=$(command -v chromium)
  elif command -v chromium-browser >/dev/null 2>&1; then
    chrome=$(command -v chromium-browser)
  else
    echo "нет Chrome/Chromium — логин стенда через xdg-open не заведётся" >&2
    chrome=/opt/google/chrome/chrome
  fi
  local qlog qdisp qproxybin qprofile qchrome qlogin proxy_lines
  qlog=$(printf '%q' "$VAR/xdg-open.log")
  qdisp=$(printf '%q' "$DISP")
  qproxybin=$(printf '%q' "$CURSOR_PROXY")
  qprofile=$(printf '%q' "$PROFILE")
  qchrome=$(printf '%q' "$chrome")
  qlogin=$(printf '%q' "$PROFILE/chrome-login")
  proxy_lines=""
  if [ -n "$PROXY_HTTP" ]; then
    proxy_lines="  --proxy-server=$(printf '%q' "$PROXY_HTTP") \\
  --proxy-bypass-list=$(printf '%q' 'localhost,127.0.0.1,::1') \\
"
  fi
  # URL в лог не пишется: в нём код логина. DevTools не поднимается.
  cat > "$BIN/xdg-open" <<EOF
#!/bin/sh
echo "\$(date -Iseconds) xdg-open" >> $qlog
url="\$1"
case "\$url" in
  cursor:*|cursor://*)
    exec env DISPLAY=$qdisp \\
      $qproxybin --user-data-dir=$qprofile --open-url "\$url"
    ;;
esac
exec env DISPLAY=$qdisp \\
  GTK_IM_MODULE=xim QT_IM_MODULE=xim XMODIFIERS= \\
  $qchrome \\
  --user-data-dir=$qlogin \\
${proxy_lines}  --ozone-platform=x11 \\
  --no-first-run --no-default-browser-check \\
  --window-size=1280,900 \\
  "\$@"
EOF
  chmod +x "$BIN/xdg-open"
}

write_state() {
  mkdir -p "$VAR"
  chmod 700 "$PROFILE" 2>/dev/null || true
  cat > "$STATE" <<EOF
DISPLAY=$DISP
PROFILE=$PROFILE
WORKSPACE=$WORKSPACE
VNC_PORT=$VNC_PORT
XSERVER=${STAND_XSERVER:-${XSERVER:-unknown}}
XSERVER_PID=${STAND_XSERVER_PID:-${XSERVER_PID:-}}
DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-}
CURSOR_PID=$(stand_cursor_pids | head -1)
EOF
}

load_state() {
  # Не source: файл мог бы выполнить подстановку. Дисплей стенда берётся
  # из окружения хоста, не из этого файла (иначе мёртвый :105 и DISPLAY=:1
  # в state отправили бы клики на стол).
  [ -f "$STATE" ] || return 1
  local line k v
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    k=${line%%=*}
    v=${line#*=}
    case "$k" in
      XSERVER|XSERVER_PID|DBUS_SESSION_BUS_ADDRESS) ;;
      *) continue ;;
    esac
    case "$v" in
      *'$('*|*'`'*)
        echo "state.env: отказ, в $k есть подстановка команды" >&2
        return 1 ;;
    esac
    printf -v "$k" '%s' "$v"
  done < "$STATE"
}

# Подхватить уже живой :105 (волны 2–4 руками), не поднимая второй Xorg.
adopt_if_live() {
  xdpyinfo -display "$DISP" >/dev/null 2>&1 || return 1
  STAND_XSERVER="${STAND_XSERVER:-xorg-nvidia}"
  STAND_XSERVER_PID=$(stand_xserver_pid "$DISP" "${STAND_XSERVER_PID:-}")
  local addr
  addr=$(stand_dbus || true)
  [ -n "$addr" ] && DBUS_SESSION_BUS_ADDRESS=$addr
  write_state
  return 0
}

cached_email() {
  local db="$PROFILE/User/globalStorage/state.vscdb"
  [ -f "$db" ] || { echo "(нет state.vscdb)"; return; }
  python3 - "$db" <<'PY' 2>/dev/null || echo "(sqlite недоступен)"
import sqlite3, sys
con = sqlite3.connect(f"file:{sys.argv[1]}?mode=ro", uri=True)
row = con.execute("select value from ItemTable where key='cursorAuth/cachedEmail'").fetchone()
print(row[0] if row else "(не залогинен)")
PY
}

ensure_not_live_profile() {
  local live
  live=$(live_cursor_pid)
  if [ -f "$PROFILE/code.lock" ] && [ -n "$live" ]; then
    local ours
    ours=$(tr -d ' \n' < "$PROFILE/code.lock" 2>/dev/null || true)
    if [ -n "$ours" ] && [ "$ours" = "$live" ]; then
      echo "Отказ: code.lock стенда совпал с живым Cursor ($live). --user-data-dir сломан." >&2
      exit 1
    fi
  fi
}

cmd_status() {
  local m1 xpid email
  m1=$(mouse1)
  echo "стенд  $DISP  профиль $PROFILE"
  echo "мышь стола ($ORIG_DISPLAY)  $m1"
  echo "живой Cursor  pid=$(live_cursor_pid)  lock=$LIVE_LOCK"
  if xdpyinfo -display "$DISP" >/dev/null 2>&1; then
    xpid=$(stand_xserver_pid "$DISP" "")
    echo "экран  жив  pid=${xpid:-?}  ($(ps -o args= -p "${xpid:-0}" 2>/dev/null | tr -s ' ' | cut -c1-80))"
  else
    echo "экран  НЕТ"
  fi
  local pids
  pids=$(stand_cursor_pids | tr '\n' ' ')
  if [ -n "${pids% }" ]; then
    echo "cursor стенда  pid $pids  lock=$(tr -d '\n' < "$PROFILE/code.lock" 2>/dev/null || echo none)"
  else
    echo "cursor стенда  НЕТ"
  fi
  email=$(cached_email)
  echo "логин  $email"
  local wp
  wp=$(stand_worker_pids | tr '\n' ' ')
  echo "worker стенда  ${wp:-нет}  (живой ~/.config/Cursor не показываю — в cmdline бывает ключ)"
  if DISPLAY="$DISP" xdotool search --name 'Cursor Agents' >/dev/null 2>&1; then
    echo "окно  Cursor Agents на $DISP"
  else
    echo "окно  Cursor Agents на $DISP нет"
  fi
  if port_busy "$VNC_PORT"; then echo "vnc  localhost:$VNC_PORT слушает"; else echo "vnc  $VNC_PORT нет"; fi
  local pkg checked
  pkg=$(cursor_pkg_ver || true)
  if [ -f "$VAR/ui-checked" ]; then
    checked=$(tr -d ' \n' < "$VAR/ui-checked")
    if [ -n "$pkg" ] && [ "$pkg" != "$checked" ]; then
      echo "предупреждение: Cursor обновлён до $pkg, handoff не проверен (ui-checked $checked)"
    fi
  else
    echo "предупреждение: handoff --dry-run ещё не записан в ui-checked"
  fi
  echo "справка якорей  UI_CALIBRATED=$UI_CALIBRATED (номер версии handoff не запрещает)"
  adopt_if_live >/dev/null 2>&1 || true
}

# Хост и порт из URL прокси. userinfo не печатается.
# http://user:pass@127.0.0.1:10816 → хост 127.0.0.1, порт 10816.
proxy_host() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
if not u.hostname:
    sys.exit(1)
print(u.hostname)
PY
}

proxy_port() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import urlparse
u = urlparse(sys.argv[1])
if not u.port:
    sys.exit(1)
print(u.port)
PY
}

# 0 — локальный прокси слушает, либо хост не локальный (проверку порта пропускаем).
require_local_proxy_port() {
  local host port
  host=$(proxy_host "$1") || return 1
  port=$(proxy_port "$1") || return 1
  if [ "$host" = "127.0.0.1" ] || [ "$host" = "localhost" ]; then
    port_busy "$port" || return 1
  fi
  return 0
}

ensure_vnc_pass() {
  local f="$VAR/vnc.pass"
  if [ ! -s "$f" ]; then
    ( umask 077
      VNC_PASS_FILE="$f" python3 -c 'import os, secrets; open(os.environ["VNC_PASS_FILE"], "w").write(secrets.token_urlsafe(18))'
    )
  fi
  chmod 600 "$f" || return 1
  local mode
  mode=$(stat -c %a "$f" 2>/dev/null || echo "")
  case "$mode" in
    600) ;;
    *) echo "vnc: права $f это ${mode:-?}, нужен 600" >&2; return 1 ;;
  esac
}

up_require_agents_window() {
  open_agents_window_if_needed || {
    echo "up: окно Cursor Agents на $DISP не открылось — смотри $VAR/cursor.log" >&2
    return 1
  }
  agents_window >/dev/null || {
    echo "up: окно Cursor Agents на $DISP не открылось — смотри $VAR/cursor.log" >&2
    return 1
  }
}

cmd_up() {
  [ -x "$CURSOR_PROXY" ] || { echo "нет $CURSOR_PROXY" >&2; exit 1; }
  [ -x "$STAND_DISPLAY_SH" ] || { echo "нет исполняемого $STAND_DISPLAY_SH" >&2; exit 1; }
  mkdir -p "$PROFILE" "$VAR" "$BIN"
  rm -f "$HOLD"
  chmod 700 "$PROFILE"
  ensure_not_live_profile

  if [ -n "$PROXY_HTTP" ]; then
    if ! require_local_proxy_port "$PROXY_HTTP"; then
      echo "прокси на localhost не слушает или URL не разобран — Cursor пошёл бы в обход настроенного прокси." >&2
      exit 1
    fi
  fi

  local m_before xserver xpid
  m_before=$(mouse1)

  if xdpyinfo -display "$DISP" >/dev/null 2>&1; then
    echo "экран $DISP уже жив — не поднимаю второй Xorg"
    adopt_if_live
    xserver=${STAND_XSERVER:-${XSERVER:-xorg-nvidia}}
    xpid=${STAND_XSERVER_PID:-${XSERVER_PID:-}}
  else
    stand_start_xserver "$DISP" "cursor-stand"
    xserver="$STAND_XSERVER"; xpid="$STAND_XSERVER_PID"
  fi

  export DISPLAY="$DISP"
  local addr
  addr=$(stand_dbus || true)
  if [ -z "$addr" ]; then
    if [ -n "$(stand_cursor_pids)" ]; then
      echo "Cursor стенда жив, шину dbus не прочитал — новую не завожу (B-247)." >&2
    else
      addr=$(dbus-daemon --session --fork --print-address=1)
    fi
  fi
  [ -n "$addr" ] && export DBUS_SESSION_BUS_ADDRESS="$addr"
  unset WAYLAND_DISPLAY || true
  export GDK_BACKEND=x11 QT_QPA_PLATFORM=xcb
  export GTK_IM_MODULE=xim QT_IM_MODULE=xim XMODIFIERS=""
  export XDG_CURRENT_DESKTOP=openbox
  export PATH="$BIN:$PATH"

  if ! DISPLAY="$DISP" xdotool search --class Openbox >/dev/null 2>&1; then
    DISPLAY="$DISP" openbox >>"$VAR/openbox.log" 2>&1 & disown
    sleep 1
  fi

  if port_busy "$VNC_PORT"; then
    echo "VNC $VNC_PORT уже слушает — не трогаю"
  else
    ensure_vnc_pass || return 1
    x11vnc -display "$DISP" -rfbport "$VNC_PORT" -rfbportv6 "$VNC_PORT" \
      -localhost -forever -shared -passwdfile "$VAR/vnc.pass" \
      >>"$VAR/x11vnc.log" 2>&1 & disown
    echo "VNC пароль в $VAR/vnc.pass (0600), в лог и git не пишется"
    sleep 1
  fi

  write_xdg_open

  if [ -n "$(stand_cursor_pids)" ]; then
    echo "Cursor стенда уже запущен (pid $(stand_cursor_pids | head -1))"
  else
    # env уже export'нут выше. Не писать DBUS=... словом перед командой:
    # bash не считает развёртку ${var:+NAME=value} присваиванием и ищет файл.
    # Без пути к проекту: иначе Electron открывает IDE «… - Cursor», не glass
    # (замер park→up 19.09.2026). Папка нужна только handoff.
    "$CURSOR_PROXY" \
        --user-data-dir="$PROFILE" \
        --ozone-platform=x11 \
        --password-store=basic \
        >>"$VAR/cursor.log" 2>&1 & disown
    sleep 8
  fi

  up_require_agents_window || return 1

  STAND_XSERVER=$xserver STAND_XSERVER_PID=$xpid write_state
  ensure_not_live_profile

  local m_after
  m_after=$(mouse1)
  echo "стенд Cursor:"
  echo "  дисплей   $DISP  ($xserver pid ${xpid:-?})"
  echo "  профиль   $PROFILE"
  echo "  воркспейс $WORKSPACE"
  echo "  VNC       localhost:$VNC_PORT"
  echo "  логин     $(cached_email)"
  echo "  мышь $ORIG_DISPLAY  до $m_before  после $m_after"
  if [ "$m_before" != "$m_after" ] && [ "$m_after" != "unavailable" ]; then
    echo "  ВНИМАНИЕ: мышь стола сдвинулась. Если это не владелец за столом — изоляция сломана." >&2
  fi
}

cmd_shot() {
  adopt_if_live || load_state || { echo "стенд не поднят" >&2; exit 1; }
  mkdir -p "$VAR/shots"
  local out="$VAR/shots/$(date +%Y%m%dT%H%M%S).png"
  DISPLAY="$DISP" scrot -o "$out"
  echo "$out"
}

cmd_park() {
  load_state || adopt_if_live || { echo "стенд не поднят" >&2; exit 1; }
  ensure_not_live_profile
  local pids
  mapfile -t pids < <(stand_cursor_pids; stand_worker_pids)
  if [ "${#pids[@]}" -eq 0 ]; then
    touch "$HOLD"
    echo "Cursor стенда уже нет. Экран $DISP оставлен."
    return
  fi
  touch "$HOLD"
  kill_pids "${pids[@]}"
  sleep 2
  echo "Cursor стенда остановлен. Экран $DISP и VNC оставлены (down — убрать VNC, down-display — экран)."
}

cmd_down() {
  cmd_park
  local pid
  for pid in $(pgrep -f "x11vnc -display $DISP" 2>/dev/null || true); do
    kill_pids "$pid"
  done
  echo "VNC $DISP остановлен, если был."
}

cmd_down_display() {
  load_state || adopt_if_live || { echo "стенд не поднят" >&2; exit 1; }
  if [ -n "$(stand_cursor_pids)" ]; then
    echo "Cursor стенда ещё работает — сначала park или down." >&2
    exit 1
  fi
  stand_stop_xserver "$DISP" "${XSERVER:-}" "${XSERVER_PID:-}"
  echo "…это был экран стенда Cursor ($DISP)."
}

# Печать на :105. xdotool type молчит из-за IBus (волна 3/4).
clip_paste() {
  local text=$1 gotf
  # xclip остаётся в фоне держать буфер и наследует stdout/stderr: вызывающий,
  # который читает вывод скрипта через конвейер, висел до тайм-аута (07.10.2026).
  # ctrl+v только если буфер этого DISPLAY совпал с текстом: иначе ушла бы
  # прошлая вставка (пароль, чужой промпт) и handoff нажал бы Return.
  # Сравнение через файл: $(xclip -o) съедает хвостовые переводы строк.
  gotf=$(mktemp)
  if ! printf '%s' "$text" | xclip -selection clipboard -display "$DISP" -i >/dev/null 2>&1; then
    rm -f "$gotf"
    echo "clip_paste: xclip не записал буфер на $DISP — ctrl+v не жму" >&2
    return 1
  fi
  sleep 0.15
  if ! xclip -selection clipboard -display "$DISP" -o >"$gotf" 2>/dev/null \
    || ! printf '%s' "$text" | cmp -s - "$gotf"; then
    rm -f "$gotf"
    echo "clip_paste: в буфере $DISP не тот текст — ctrl+v не жму" >&2
    return 1
  fi
  rm -f "$gotf"
  DISPLAY="$DISP" xdotool key --clearmodifiers ctrl+v
  sleep 0.3
}

# Y выделенной строки в сайдбаре glass (не New Chat). Замер 19.09.2026.
# Правая панель (Changes / Browser / Terminal / File) сдвигает чат влево, и
# якоря handoff с зонами под центрированную вёрстку промахиваются (10.10.2026:
# «не найден якорь folder-search» при открытой панели). Панель узнаём по её
# вертикальной границе правее сайдбара; печатаем x границы, код 0 — открыта.
right_panel_x() {
  local shot="$VAR/shots/_rpanel.png"
  mkdir -p "$VAR/shots"
  DISPLAY="$DISP" import -window root "$shot" 2>/dev/null || DISPLAY="$DISP" scrot -o "$shot"
  python3 - "$shot" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("L")
px = im.load()
w, h = im.size
ys = range(120, min(1000, h), 4)
for x in range(700, min(1760, w - 5)):
    hits = sum(1 for y in ys if abs(px[x, y] - px[x - 4, y]) >= 3 and abs(px[x, y] - px[x + 4, y]) >= 3)
    if hits >= 0.85 * len(ys):
        print(x)
        sys.exit(0)
sys.exit(1)
PY
}

# Закрыть правую панель, если открыта: кнопка-переключатель в правом верхнем
# углу окна. Проверяем результат снимком, вслепую второй раз не жмём.
close_right_panel() {
  local x
  x=$(right_panel_x) || return 0
  echo "правая панель открыта (граница x=$x) — закрываю"
  DISPLAY="$DISP" xdotool mousemove --sync 1897 52 click 1
  sleep 1.0
  DISPLAY="$DISP" xdotool mousemove --sync 1100 400
  if x=$(right_panel_x); then
    echo "правая панель не закрылась (граница x=$x)" >&2
    return 1
  fi
}

sidebar_selected_y() {
  local shot="$VAR/shots/_sidebar.png"
  mkdir -p "$VAR/shots"
  # Увести указатель из сайдбара: строка под ним тоже подсвечена (наведение) и
  # могла быть принята за выделенную — rename/archive попали бы в чужую сессию.
  DISPLAY="$DISP" xdotool mousemove --sync 1100 400
  sleep 0.4
  DISPLAY="$DISP" import -window root "$shot" 2>/dev/null || DISPLAY="$DISP" scrot -o "$shot"
  python3 - "$shot" <<'PY'
# Выделенная строка сайдбара — по фону у краёв строки (x=12..14 и 244..246), где
# нет текста: фон строки ОТЛИЧАЕТСЯ от базового фона списка — в тёмной теме он
# светлее, в светлой темнее. Тема стенда следует за системной
# (window.autoDetectColorScheme), то есть меняется по времени суток: 10.10.2026
# днём rename не находил строку, потому что искал только «светлее».
# Средняя яркость строки с
# текстом не годится: у нижней строки подсветка затухает (край списка), и
# порог «среднее+12» рвал выделенную строку светлой темы (y около 1000).
# Скан до 1038: ниже — строка аккаунта.
import sys
from collections import Counter
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
px = im.load()
cols = [c for c in (12, 14, 244, 246) if c < im.size[0]]
rows = []
for y in range(110, min(1038, im.size[1])):
    rows.append(([sum(px[c, y]) // 3 for c in cols], y))
if not rows:
    sys.exit(1)
base = Counter(v for r, _ in rows for v in r).most_common(1)[0][0]
# Отклонение строки — наименьшее по всем краевым столбцам: выделение красит
# строку целиком, случайный пиксель текста или иконки — нет.
vals = [(min(abs(v - base) for v in r), y) for r, y in rows]
segs, seg = [], None
for v, y in vals:
    if v >= 2:
        if seg is None:
            seg = [y, y, v]
        else:
            seg[1] = y
            seg[2] = max(seg[2], v)
    else:
        if seg and 16 <= seg[1] - seg[0] <= 48:
            segs.append(seg)
        seg = None
if seg and 16 <= seg[1] - seg[0] <= 48:
    segs.append(seg)
if not segs:
    sys.exit(1)
best = max(segs, key=lambda z: z[2])
print((best[0] + best[1]) // 2)
PY
}

# poll_stdout_eq SEC WANT CMD... — stdout CMD каждые CURSOR_STAND_POLL_INTERVAL
# (дефолт 0.5 с), пока не равен WANT или не выйдет потолок SEC.
# Печатает последний stdout. Код 0 — совпало.
poll_stdout_eq() {
  local sec=$1 want=$2
  shift 2
  local i n got interval
  interval=${CURSOR_STAND_POLL_INTERVAL:-0.5}
  n=$(awk -v s="$sec" -v i="$interval" 'BEGIN { n=int((s/i)+0.5); if (n<1) n=1; print n }')
  got=""
  i=0
  while [ "$i" -lt "$n" ]; do
    i=$((i + 1))
    sleep "$interval"
    got=$("$@" 2>/dev/null || true)
    if [ "$got" = "$want" ]; then
      printf '%s\n' "$got"
      return 0
    fi
  done
  printf '%s\n' "$got"
  return 1
}

# Имя строки cloudAgentRepository. Пустой вывод и код 0, если записи ещё нет.
agent_name_of() {
  local line=""
  if [ "${1:-}" = "--id" ]; then
    line=$(python3 "$GLASS_AGENTS" resolve --id "$2" 2>/dev/null | sed -n '2p' || true)
  else
    line=$(python3 "$GLASS_AGENTS" resolve --current 2>/dev/null | sed -n '2p' || true)
  fi
  printf '%s\n' "$line"
}

# Правый клик по ТЕКУЩЕЙ выделенной строке → Pin/Unpin, Rename.
# Имя — вставка, не xdotool type (IBus). Перед этим сессию надо открыть (glass_focus_bcid).
# Второй аргумент — bc-id: ждать имя этой строки, а не той, что окажется selected.
glass_rename() {
  local name=$1 id=${2:-} y
  [ -n "$name" ] || { echo "rename: пустое имя" >&2; return 1; }
  [ -n "$id" ] || { echo "rename: нужен bc-id, без него строку не кликаю" >&2; return 1; }
  agents_window >/dev/null || return 1
  local sel current
  sel=$(python3 "$GLASS_AGENTS" selected | head -1)
  if [ "$sel" != "$id" ]; then
    echo "rename: выделена '$sel', ждали $id — не кликаю" >&2
    return 1
  fi
  current=$(python3 "$GLASS_AGENTS" resolve --id "$id" 2>/dev/null | sed -n '2p' || true)
  [ -n "$current" ] || { echo "rename: нет текущего имени у $id" >&2; return 1; }
  y=$(sidebar_selected_y) || { echo "rename: не нашёл выделенную сессию в сайдбаре" >&2; return 1; }
  if [ "$y" -lt 130 ]; then
    echo "rename: выделено New Chat, не сессия (y=$y)" >&2
    return 1
  fi
  python3 "$GLASS_AGENTS" row-name "$VAR/shots/_sidebar.png" "$y" "$current" || {
    echo "rename: строка y=$y не совпала с именем — не кликаю" >&2
    return 1
  }
  DISPLAY="$DISP" xdotool mousemove --sync 120 "$y"
  sleep 0.15
  DISPLAY="$DISP" xdotool click --clearmodifiers 3
  sleep 0.5
  # Пункт Rename — по надписи в меню, не «Down Down Return»: у нижних строк
  # меню открывается вверх, у черновиков состав пунктов другой.
  local shot pos rx ry got
  mkdir -p "$VAR/shots"
  shot="$VAR/shots/_rename-menu.png"
  DISPLAY="$DISP" import -window root "$shot" 2>/dev/null || DISPLAY="$DISP" scrot -o "$shot"
  pos=$(python3 "$GLASS_AGENTS" menu-pos "$shot" Rename) || {
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    echo "rename: в меню строки (y=$y) нет пункта Rename. Снимок $shot" >&2
    return 1
  }
  read -r rx ry <<<"$pos"
  DISPLAY="$DISP" xdotool mousemove --sync "$rx" "$ry" click --clearmodifiers 1
  sleep 0.5
  DISPLAY="$DISP" xdotool key --clearmodifiers ctrl+a
  sleep 0.1
  clip_paste "$name"
  DISPLAY="$DISP" xdotool key --clearmodifiers Return
  # Итог — по sqlite этой bc-id, не по факту нажатий. Потолок SQLITE_UI_WAIT_SEC.
  local got=""
  if [ -n "$id" ]; then
    got=$(poll_stdout_eq "$SQLITE_UI_WAIT_SEC" "$name" agent_name_of --id "$id") || true
  else
    got=$(poll_stdout_eq "$SQLITE_UI_WAIT_SEC" "$name" agent_name_of) || true
  fi
  if [ "$got" = "$name" ]; then
    echo "переименовано в '$name' (сайдбар y=$y)"
    return 0
  fi
  echo "rename: имя в sqlite '$got', ждали '$name' (сайдбар y=$y, ждали ${SQLITE_UI_WAIT_SEC} с). Снимок меню $shot" >&2
  return 1
}

# Ctrl+Alt+P → вставить bc-id → Return, только если палитра показала эту сессию.
# sqlite selectedAgent должен совпасть, иначе не трогаем имя.
glass_focus_bcid() {
  local id=$1 expected=$2 shot sel i
  [ -n "$id" ] || return 1
  sel=$(python3 "$GLASS_AGENTS" selected | head -1)
  if [ "$sel" = "$id" ]; then
    echo "уже открыта $id ($expected)"
    return 0
  fi
  agents_window >/dev/null || return 1
  DISPLAY="$DISP" xdotool key --clearmodifiers Escape
  sleep 0.2
  DISPLAY="$DISP" xdotool key --clearmodifiers Escape
  sleep 0.25
  mkdir -p "$VAR/shots"
  shot="$VAR/shots/_search-agents.png"
  # Вставлять id только в открытую палитру: иначе он попадает в поле ввода сессии.
  local opened=0 try
  for try in 1 2 3; do
    DISPLAY="$DISP" xdotool key --clearmodifiers ctrl+alt+p
    sleep 0.7
    DISPLAY="$DISP" import -window root "$shot" 2>/dev/null || DISPLAY="$DISP" scrot -o "$shot"
    if python3 "$GLASS_AGENTS" palette-open "$shot"; then opened=1; break; fi
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    sleep 0.5
  done
  [ "$opened" = 1 ] || { echo "Search Agents не открылся — id не вставляю" >&2; return 1; }
  clip_paste "$id"
  sleep 0.5
  DISPLAY="$DISP" import -window root "$shot" 2>/dev/null || DISPLAY="$DISP" scrot -o "$shot"
  python3 "$GLASS_AGENTS" palette-ok "$shot" "$expected" "$id" || {
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    return 1
  }
  DISPLAY="$DISP" xdotool key --clearmodifiers Return
  for i in 1 2 3 4 5; do
    sleep 0.5
    sel=$(python3 "$GLASS_AGENTS" selected | head -1)
    if [ "$sel" = "$id" ]; then
      echo "открыта $id ($expected)"
      return 0
    fi
  done
  echo "rename: после Search Agents выделена '$sel', ждали $id. Имя не меняю." >&2
  return 1
}

cmd_rename() {
  local bc_id="" from="" current=0 new=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -i|--id)
        [ $# -ge 2 ] || { echo "rename: $1 ждёт bc-id" >&2; exit 1; }
        bc_id=$2; shift 2 ;;
      --id=*) bc_id=${1#--id=}; shift ;;
      -f|--from)
        [ $# -ge 2 ] || { echo "rename: $1 ждёт текущее имя" >&2; exit 1; }
        from=$2; shift 2 ;;
      --from=*) from=${1#--from=}; shift ;;
      -c|--current) current=1; shift ;;
      --) shift; break ;;
      -*) echo "rename: неизвестный флаг $1" >&2; exit 1 ;;
      *) break ;;
    esac
  done
  if [ -z "$bc_id" ] && [ -z "$from" ] && [ "$current" -eq 0 ]; then
    if [ $# -ge 2 ]; then
      from=$1; shift
    fi
  fi
  new="${*:-}"
  if [ -z "$new" ]; then
    echo "rename: укажи сессию и новое имя:" >&2
    echo "  $0 rename --id bc-… новое-имя" >&2
    echo "  $0 rename --from 'Pong response output' pong" >&2
    echo "  $0 rename --current новое-имя" >&2
    echo "  $0 rename 'старое имя' новое-имя" >&2
    exit 1
  fi
  if [ -z "$bc_id" ] && [ -z "$from" ] && [ "$current" -eq 0 ]; then
    echo "rename: без селектора не угадаю вкладку. Нужны --id, --from, --current или два аргумента." >&2
    exit 1
  fi
  if [ -n "$bc_id" ] && [ -n "$from" ]; then
    echo "rename: --id и --from вместе нельзя" >&2; exit 1
  fi
  if [ "$current" -eq 1 ] && { [ -n "$bc_id" ] || [ -n "$from" ]; }; then
    echo "rename: --current вместе с --id/--from нельзя" >&2; exit 1
  fi

  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  export DISPLAY="$DISP"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS

  local resolved id expected m_before m_after
  if [ "$current" -eq 1 ]; then
    resolved=$(python3 "$GLASS_AGENTS" resolve --current) || exit 1
  elif [ -n "$bc_id" ]; then
    resolved=$(python3 "$GLASS_AGENTS" resolve --id "$bc_id") || exit 1
  else
    resolved=$(python3 "$GLASS_AGENTS" resolve --from "$from") || exit 1
  fi
  id=$(printf '%s\n' "$resolved" | sed -n '1p')
  expected=$(printf '%s\n' "$resolved" | sed -n '2p')
  m_before=$(mouse1)
  glass_focus_bcid "$id" "$expected" || exit 1
  glass_rename "$new" "$id" || exit 1
  m_after=$(mouse1)
  echo "сессия $id  было '$expected'  стало '$new'"
  echo "мышь $ORIG_DISPLAY  до $m_before  после $m_after"
}

# После park→up Cursor с путём к папке открывает IDE, не glass (замер 19.09.2026).
# Путь в argv больше не передаём; если всё же IDE — палитра Open Agents Window.
open_agents_window_if_needed() {
  local i w
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    if DISPLAY="$DISP" xdotool search --name 'Cursor Agents' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  w=$(DISPLAY="$DISP" xdotool search --class cursor 2>/dev/null | tail -1 || true)
  if [ -z "$w" ]; then
    echo "up: на $DISP нет окна cursor" >&2
    return 1
  fi
  echo "up: glass нет — Open Agents Window из IDE"
  DISPLAY="$DISP" xdotool windowactivate --sync "$w"
  sleep 0.3
  DISPLAY="$DISP" xdotool key --clearmodifiers ctrl+shift+p
  sleep 0.7
  clip_paste "Open Agents Window"
  sleep 0.4
  DISPLAY="$DISP" xdotool key --clearmodifiers Return
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if DISPLAY="$DISP" xdotool search --name 'Cursor Agents' >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

agents_window() {
  local w
  w=$(DISPLAY="$DISP" xdotool search --name 'Cursor Agents' 2>/dev/null | tail -1 || true)
  [ -n "$w" ] || { echo "нет окна Cursor Agents на $DISP" >&2; return 1; }
  DISPLAY="$DISP" xdotool windowactivate --sync "$w"
  DISPLAY="$DISP" xdotool windowmove "$w" 0 0
  DISPLAY="$DISP" xdotool windowsize "$w" 1920 1080
  sleep 0.4
  echo "$w"
}

resolve_workspace() {
  local raw=$1 p
  [ -n "$raw" ] || return 1
  [ -d "$raw" ] || { echo "handoff: нет каталога '$raw'" >&2; return 1; }
  p=$(readlink -f -- "$raw") || return 1
  [ -d "$p" ] || { echo "handoff: '$p' не каталог" >&2; return 1; }
  case "$p" in
    "$HOME/.config/Cursor"|"$HOME/.config/Cursor"/*|"$PROFILE"|"$PROFILE"/*)
      echo "handoff: отказ, это профиль Cursor, не проект: $p" >&2
      return 1 ;;
  esac
  printf '%s\n' "$p"
}

cursor_pkg_ver() {
  local v
  v=$(dpkg-query -W -f='${Version}' cursor 2>/dev/null | cut -d- -f1 || true)
  if [ -z "$v" ] && [ -f /usr/share/cursor/resources/app/package.json ]; then
    v=$(python3 -c 'import json; print(json.load(open("/usr/share/cursor/resources/app/package.json")).get("version") or "")' 2>/dev/null || true)
  fi
  printf '%s\n' "$v"
}

# Мажор.минор: 3.23.23 → 3.23, 3.21 → 3.21 (не ${ver%.*}: у 3.21 это даст 3).
cursor_ver_mm() {
  printf '%s\n' "$1" | awk -F. '{print $1"."$2}'
}

write_ui_checked() {
  mkdir -p "$VAR"
  cursor_pkg_ver > "$VAR/ui-checked"
}

# Версию пакета handoff не проверяет (BL-007). Отдельной функции-заглушки нет.

handoff_shot() {
  mkdir -p "$VAR/shots"
  local out="$VAR/shots/${1:-handoff}-$(date +%H%M%S).png"
  DISPLAY="$DISP" import -window root "$out" 2>/dev/null || DISPLAY="$DISP" scrot -o "$out"
  printf '%s\n' "$out"
}

handoff_anchor_xy() {
  local name=$1 shot=$2 pos
  pos=$(python3 "$GLASS_AGENTS" anchor "$shot" "$name") || return 1
  printf '%s\n' "$pos"
}

# Снять toast «Agent starting expensive processes» (крестик).
# Диалог «Move agent while it's working?» — Cancel/Escape и отказ (никогда Stop and Move).
# Печатает путь снимка. Код: 0 ок, 2 move-working (отказ вызывающему).
stand_dismiss_overlays() {
  local tag=${1:-overlay} shot line kind x y rc tries=0
  while [ "$tries" -lt 4 ]; do
    tries=$((tries + 1))
    shot=$(handoff_shot "$tag")
    rc=0
    line=$(python3 "$GLASS_AGENTS" overlay-scan "$shot" 2>/dev/null) || rc=$?
    if [ "$rc" -eq 1 ] || [ -z "$line" ]; then
      printf '%s\n' "$shot"
      return 0
    fi
    kind=$(printf '%s\n' "$line" | awk -F'\t' '{print $1}')
    x=$(printf '%s\n' "$line" | awk -F'\t' '{print $2}')
    y=$(printf '%s\n' "$line" | awk -F'\t' '{print $3}')
    if [ "$kind" = "move-working" ]; then
      echo "stand: диалог «Move agent while it's working?» — Cancel (не Stop and Move)" >&2
      if [ "$x" != "-" ] && [ -n "$x" ] && [ -n "$y" ]; then
        DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
      else
        DISPLAY="$DISP" xdotool key --clearmodifiers Escape
      fi
      sleep 0.4
      handoff_shot "move-working-cancel" >/dev/null
      printf '%s\n' "$shot"
      return 2
    fi
    if [ "$kind" = "expensive-dismiss" ] && [ -n "$x" ] && [ -n "$y" ]; then
      echo "stand: закрываю toast expensive-processes крестиком $x,$y"
      DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
      sleep 0.5
      rc=0
      continue
    fi
    printf '%s\n' "$shot"
    return 0
  done
  printf '%s\n' "${shot:-}"
  return 0
}

# Конвертация уже открытого локального чата → local-rc.
# Аргументы: local_uuid (без/с bc-) workspace. Код 0 = convert-ok.
# Общий путь для handoff и convert (13.10.2026).
glass_convert_to_rc() {
  local local_uuid=$1 ws=$2
  local shot pos x y i rc ok=0 uid
  uid=${local_uuid#bc-}
  [ -n "$uid" ] || return 1
  [ -n "$ws" ] || return 1

  shot=$(stand_dismiss_overlays h-pre-convert) || {
    echo "convert: агент ещё работает — дождись конца хода, потом convert" >&2
    return 1
  }

  if python3 "$GLASS_AGENTS" convert-ok "$uid" "$ws" >/tmp/cursor-stand-convert-ok.txt 2>&1; then
    echo "convert: уже local-rc bc-$uid"
    cat /tmp/cursor-stand-convert-ok.txt
    return 0
  fi

  shot=$(handoff_shot h-pre-footer)
  stand_dismiss_overlays h-pre-footer2 >/dev/null || {
    echo "convert: Move agent while working — отказ" >&2
    return 1
  }
  shot=$(handoff_shot h-footer)
  if ! python3 "$GLASS_AGENTS" anchor "$shot" footer-this-computer >/dev/null 2>&1; then
    echo "convert: нет футера This Computer (уже Self-Hosted или не тот экран); см. $shot" >&2
    return 1
  fi
  pos=$(handoff_anchor_xy footer-this-computer "$shot") || return 1
  read -r x y <<<"$pos"
  echo "convert: футер This Computer $x,$y"
  DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
  sleep 0.8
  shot=$(stand_dismiss_overlays h-continue-on) || {
    echo "convert: Move agent while working после футера — отказ" >&2
    return 1
  }
  python3 "$GLASS_AGENTS" anchor "$shot" convert-self-hosted >/dev/null || {
    echo "convert: нет convert-self-hosted (меню Continue on); см. $shot" >&2
    return 1
  }
  pos=$(handoff_anchor_xy convert-self-hosted "$shot") || return 1
  read -r x y <<<"$pos"
  echo "convert: Self-Hosted Worker $x,$y"
  DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
  sleep 1.0
  shot=$(stand_dismiss_overlays h-exclude) || {
    echo "convert: Move agent while working — отказ" >&2
    return 1
  }
  if python3 "$GLASS_AGENTS" anchor "$shot" exclude-changes >/dev/null 2>&1; then
    echo "convert: диалог uncommitted — клик Exclude Changes (не Include, не Enter)"
    pos=$(handoff_anchor_xy exclude-changes "$shot") || return 1
    read -r x y <<<"$pos"
    DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
  else
    echo "convert: диалога Exclude нет (чистое дерево) — жду sqlite"
  fi

  echo "convert: жду local-rc bc-$uid (до 90 с)"
  for i in $(seq 1 90); do
    rc=0
    python3 "$GLASS_AGENTS" convert-ok "$uid" "$ws" >/tmp/cursor-stand-convert-ok.txt 2>&1 || rc=$?
    if [ "$rc" -eq 0 ]; then
      ok=1
      echo "convert: convert-ok на ${i}s"
      cat /tmp/cursor-stand-convert-ok.txt
      break
    fi
    if [ $((i % 10)) -eq 0 ]; then
      echo "convert: ещё не local-rc (${i}s, rc=$rc)"
      sed -n '1,8p' /tmp/cursor-stand-convert-ok.txt 2>/dev/null || true
      stand_dismiss_overlays "h-wait-$i" >/dev/null || {
        echo "convert: Move agent while working во время ожидания — отказ" >&2
        return 1
      }
    fi
    sleep 1
  done
  if [ "$ok" != 1 ]; then
    handoff_shot "handoff-fail-convert" >/dev/null
    echo "convert ЗАБЛОКИРОВАН: bc-$uid за 90 с не стал local-rc $ws" >&2
    cat /tmp/cursor-stand-convert-ok.txt >&2 || true
    return 1
  fi
  return 0
}

# convert --id <uuid|bc-|имя> [-n имя] [--dry-run] [-w /ABS]
cmd_convert() {
  local id="" name="" dry=0 ws="" resolved rname rws sel shot
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) id=${2:-}; shift 2 ;;
      --id=*) id=${1#--id=}; shift ;;
      -n|--name) name=${2:-}; shift 2 ;;
      --name=*) name=${1#--name=}; shift ;;
      -w|--workspace) ws=${2:-}; shift 2 ;;
      --workspace=*) ws=${1#--workspace=}; shift ;;
      --dry-run) dry=1; shift ;;
      -*) echo "convert: неизвестный флаг $1" >&2; exit 1 ;;
      *) break ;;
    esac
  done
  [ -n "$id" ] || { echo "convert: нужен --id <uuid|bc-…|имя>" >&2; exit 1; }
  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  export DISPLAY="$DISP"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS
  agents_window >/dev/null || exit 1

  if resolved=$(python3 "$GLASS_AGENTS" resolve --id "$id" 2>/dev/null); then
    id=$(printf '%s\n' "$resolved" | sed -n '1p')
    rname=$(printf '%s\n' "$resolved" | sed -n '2p')
    rws=$(printf '%s\n' "$resolved" | sed -n '3p')
  elif resolved=$(python3 "$GLASS_AGENTS" resolve --from "$id" 2>/dev/null); then
    id=$(printf '%s\n' "$resolved" | sed -n '1p')
    rname=$(printf '%s\n' "$resolved" | sed -n '2p')
    rws=$(printf '%s\n' "$resolved" | sed -n '3p')
  else
    # Локальный uuid до появления в cloudAgentRepository (13.10).
    case "$id" in
      *-*-*-*-*) rname=$id; rws=$ws ;;
      *)
        echo "convert: нет сессии $id в профиле и это не uuid" >&2
        exit 1 ;;
    esac
  fi
  if [ -z "$ws" ]; then
    ws=$rws
  fi
  if [ -z "$ws" ]; then
    echo "convert: укажи -w /ABS (у локального чата workspace ещё не в sqlite)" >&2
    exit 1
  fi
  ws=$(resolve_workspace "$ws") || exit 1

  local sel_u id_u sel
  id_u=${id#bc-}
  sel=$(python3 "$GLASS_AGENTS" selected | head -1)
  sel_u=${sel#bc-}
  # Локальный uuid до convert часто нет в Search Agents (13.10) — если уже
  # открыт, не зовём палитру. Иначе пробуем focus; при провале — отказ.
  if [ "$sel_u" != "$id_u" ] && [ "$sel" != "$id" ] && [ "$sel" != "bc-$id_u" ]; then
    if ! glass_focus_bcid "$id" "${rname:-$id}" \
      && ! glass_focus_bcid "bc-$id_u" "${rname:-$id}"; then
      echo "convert: не открыл $id (локальный чат — оставь вкладку выделенной после handoff --no-convert)" >&2
      exit 1
    fi
    sel=$(python3 "$GLASS_AGENTS" selected | head -1)
    sel_u=${sel#bc-}
  else
    echo "convert: уже открыта $sel"
  fi
  if [ "$sel_u" != "$id_u" ] && [ "$sel" != "$id" ] && [ "$sel" != "bc-$id_u" ]; then
    echo "convert: открыта '$sel', ждали $id" >&2
    exit 1
  fi

  shot=$(stand_dismiss_overlays convert-open) || {
    echo "convert: агент работает — Cancel нажато; дождись конца хода" >&2
    exit 1
  }
  if python3 "$GLASS_AGENTS" stop-pos "$shot" --strict >/dev/null 2>&1; then
    echo "convert: на экране Stop — агент ещё работает, не конвертирую" >&2
    exit 1
  fi

  if [ "$dry" = 1 ]; then
    if python3 "$GLASS_AGENTS" anchor "$shot" footer-this-computer >/dev/null 2>&1; then
      echo "convert: dry-run ок, футер This Computer есть, кликов не было"
      return 0
    fi
    echo "convert: dry-run — футера This Computer нет (см. $shot)" >&2
    return 1
  fi

  glass_convert_to_rc "$id_u" "$ws" || exit 1
  local nid="bc-$id_u"
  if [ -n "$name" ]; then
    rname=$(python3 "$GLASS_AGENTS" resolve --id "$nid" 2>/dev/null | sed -n '2p' || true)
    if glass_focus_bcid "$nid" "${rname:-$name}"; then
      glass_rename "$name" "$nid" || echo "convert: local-rc есть, имя '$name' не выставилось" >&2
    fi
  fi
  echo "convert ок: $nid  $ws${name:+  имя $name}"
}

# Handoff 3.23 по якорям (BL-001/BL-003). --dry-run не жмёт Return.
# Задача — вторым сообщением (--then / --then-file); первое — короткое READY.
cmd_handoff() {
  local ws="" msg name="" dry=0 trace=0 then_msg="" then_file="" no_convert=0
  local HANDOFF_FIRST_DEFAULT='Reply with only the word READY. Do not use tools.'
  while [ $# -gt 0 ]; do
    case "$1" in
      -w|--workspace)
        [ $# -ge 2 ] || { echo "handoff: $1 ждёт путь" >&2; exit 1; }
        ws=$2; shift 2 ;;
      --workspace=*)
        ws=${1#--workspace=}; shift ;;
      -n|--name)
        [ $# -ge 2 ] || { echo "handoff: $1 ждёт имя" >&2; exit 1; }
        name=$2; shift 2 ;;
      --name=*)
        name=${1#--name=}; shift ;;
      --then)
        [ $# -ge 2 ] || { echo "handoff: --then ждёт текст" >&2; exit 1; }
        then_msg=$2; shift 2 ;;
      --then=*) then_msg=${1#--then=}; shift ;;
      --then-file)
        [ $# -ge 2 ] || { echo "handoff: --then-file ждёт путь" >&2; exit 1; }
        then_file=$2; shift 2 ;;
      --then-file=*) then_file=${1#--then-file=}; shift ;;
      --no-convert) no_convert=1; shift ;;
      --dry-run) dry=1; shift ;;
      --trace) trace=1; dry=1; shift ;;
      --) shift; break ;;
      -*) echo "handoff: неизвестный флаг $1 (нужно -w /путь, -n имя, --then, --dry-run, --trace, --no-convert)" >&2; exit 1 ;;
      *) break ;;
    esac
  done
  if [ -z "$ws" ] && [ $# -ge 1 ] && [ -d "$1" ]; then
    ws=$1; shift
  fi
  if [ -z "$ws" ]; then
    ws="${WORKSPACE_ENV:-}"
  fi
  if [ -z "$ws" ]; then
    echo "handoff: укажи папку проекта:  $0 handoff -w /path/to/project --then 'задача'" >&2
    echo "без папки convert падает на Home/No Repo (волна 4)." >&2
    exit 1
  fi
  ws=$(resolve_workspace "$ws") || exit 1
  if [ -n "$then_file" ]; then
    [ -f "$then_file" ] || { echo "handoff: нет --then-file $then_file" >&2; exit 1; }
    then_msg=$(cat "$then_file")
  fi
  msg="${*:-}"
  if [ -n "$msg" ] && [ "${#msg}" -gt 120 ]; then
    echo "handoff: длинный промпт первым сообщением запрещён (13.10: агент стартует до convert)." >&2
    echo "handoff: короткое первое (или дефолт READY) + --then 'задача' / --then-file" >&2
    exit 1
  fi
  if [ -z "$msg" ]; then
    msg=$HANDOFF_FIRST_DEFAULT
  fi

  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  export DISPLAY="$DISP"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS
  local email m_before
  email=$(cached_email)
  case "$email" in
    ''|'(нет state.vscdb)'|'(не залогинен)'|'(sqlite недоступен)')
      echo "стенд не залогинен ($email). handoff без аккаунта не конвертирует RC." >&2
      exit 1 ;;
  esac
  m_before=$(mouse1)
  local t0_ms prev_id prev_name shot pos x y
  t0_ms=$(date +%s%3N)
  t0_ms=${t0_ms%[!0-9]*}
  prev_id=$(python3 "$GLASS_AGENTS" selected | head -1)
  prev_name=""
  if [ -n "$prev_id" ]; then
    # Выделенным может быть локальный черновик без записи в профиле (после
    # archive/Discard остаётся пустой New Chat) — это не повод отказывать.
    prev_name=$(python3 "$GLASS_AGENTS" resolve --id "$prev_id" 2>/dev/null | sed -n '2p' || true)
  fi
  local wid
  wid=$(agents_window) || exit 1

  handoff_abort() {
    local why=$1
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    sleep 0.2
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    sleep 0.2
    handoff_shot "handoff-fail" >/dev/null
    echo "handoff ЗАБЛОКИРОВАН: не найден якорь $why" >&2
    if [ -n "${prev_id:-}" ]; then
      glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" >/dev/null 2>&1 || true
    fi
    exit 1
  }

  click_anchor() {
    local an=$1
    shot=$(stand_dismiss_overlays "h-$an") || handoff_abort "move-working (агент ещё работает)"
    pos=$(handoff_anchor_xy "$an" "$shot") || {
      shot=$(handoff_shot "h-$an-retry")
      stand_dismiss_overlays "h-$an-retry2" >/dev/null || true
      pos=$(handoff_anchor_xy "$an" "$shot") || handoff_abort "$an"
    }
    read -r x y <<<"$pos"
    echo "handoff: якорь $an $x,$y"
    DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
  }

  # --trace: после каждого клика/клавиши/вставки 4 с + created-since.
  # На первой новой сессии — стоп, Stop, архив. Не продолжать.
  trace_hit() {
    local step=$1 shot_hit nid nname line
    shot_hit=$(handoff_shot "trace-HIT-$step")
    echo "TRACE HIT last_action=$step  $(date +%H:%M:%S)  shot=$shot_hit" >&2
    python3 "$GLASS_AGENTS" created-since "$t0_ms" >&2 || true
    line=$(python3 "$GLASS_AGENTS" created-since "$t0_ms" | head -1 || true)
    nid=$(printf '%s\n' "$line" | cut -f1)
    nname=$(printf '%s\n' "$line" | cut -f3)
    if [ -z "$nid" ] || [ "$nid" = "$prev_id" ]; then
      echo "TRACE: не разобрал новую bc-id, Stop не жму" >&2
      exit 2
    fi
    case "$ARCHIVE_PROTECTED_IDS" in
      *"$nid"*) echo "TRACE: новая id в защищённых — Stop не жму $nid" >&2; exit 2 ;;
    esac
    python3 "$GLASS_AGENTS" show "$nid" >&2 || true
    if glass_stop "$nid" "${nname:-$nid}"; then
      # cmd_archive делает exit 1 — субоболочка, чтобы вернуть вкладку prev_id.
      ( cmd_archive --id "$nid" ) || echo "TRACE: archive не удался у $nid" >&2
    else
      echo "TRACE: Stop не вышло, архив не ставлю пока status=1 ($nid)" >&2
    fi
    if [ -n "$prev_id" ]; then
      glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" >/dev/null 2>&1 || true
    fi
    echo "TRACE: виновник last_action=$step  $nid  $nname"
    exit 2
  }

  last_trace_step=""
  trace_after() {
    local step=$1
    [ "$trace" = 1 ] || return 0
    last_trace_step=$step
    echo "TRACE after=$step  wait 4s  $(date +%H:%M:%S)  t0=$t0_ms"
    sleep 4
    if python3 "$GLASS_AGENTS" created-since "$t0_ms" >/dev/null 2>&1; then
      trace_hit "$step"
    fi
    echo "TRACE none after=$step  $(date +%H:%M:%S)"
  }

  stand_dismiss_overlays h-start >/dev/null || handoff_abort "move-working (агент ещё работает)"
  click_anchor new-chat
  trace_after click-new-chat
  sleep 1.0
  close_right_panel || handoff_abort "правая панель не закрылась"
  shot=$(stand_dismiss_overlays h-newchat) || handoff_abort "move-working"
  python3 "$GLASS_AGENTS" anchor "$shot" plan-idea >/dev/null || handoff_abort "plan-idea (после New Chat)"
  echo "handoff: новый чат (plan-idea есть)"

  click_anchor folder-chip
  trace_after click-folder-chip
  sleep 0.8
  shot=$(handoff_shot h-picker)
  if ! python3 "$GLASS_AGENTS" anchor "$shot" folder-search >/dev/null 2>&1; then
    if [ "$trace" = 1 ]; then
      echo "TRACE: пикер закрылся или OCR — повторный клик folder-chip (без второго 4с)"
      click_anchor folder-chip
      sleep 0.8
      shot=$(handoff_shot h-picker)
    fi
    python3 "$GLASS_AGENTS" anchor "$shot" folder-search >/dev/null || handoff_abort "folder-search"
  fi
  click_anchor folder-search
  trace_after click-folder-search
  sleep 0.2
  clip_paste "$ws"
  trace_after paste-path
  sleep 0.8
  shot=$(handoff_shot h-filtered)
  if python3 "$GLASS_AGENTS" anchor "$shot" recents >/dev/null 2>&1; then
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    handoff_abort "recents (пикер не отфильтровался, Return взял бы GitHub)"
  fi
  # Пока пикер открыт, чип за ним часто Self-Hosted — это ещё не среда после выбора.
  # Стоп по Worker/Environment — только после folder-result.
  click_anchor folder-result
  trace_after click-folder-result
  sleep 1.0
  # 3.30 (14.11.2026): выбор папки-репо открывает правую панель Changes уже после
  # New Chat — чип среды уезжает влево, якоря промахиваются. Закрываем ещё раз.
  sleep 1.0
  close_right_panel || handoff_abort "правая панель не закрылась (после выбора папки)"
  shot=$(handoff_shot h-folder-ok)
  python3 "$GLASS_AGENTS" anchor "$shot" env-this-computer >/dev/null || handoff_abort "env-this-computer"
  if python3 "$GLASS_AGENTS" anchor "$shot" env-self-hosted >/dev/null 2>&1; then
    handoff_abort "env-self-hosted (нужен plain This Computer, не Worker)"
  fi
  if python3 "$GLASS_AGENTS" anchor "$shot" env-cloud >/dev/null 2>&1; then
    handoff_abort "env-cloud (среда осталась Cloud)"
  fi
  if python3 "$GLASS_AGENTS" anchor "$shot" set-environment >/dev/null 2>&1; then
    handoff_abort "set-environment (это Environment, не local-rc)"
  fi
  echo "handoff: папка $ws, среда This Computer (без /remote-control)"

  pos=$(python3 "$GLASS_AGENTS" composer-pos "$shot" "$(hostname)") || handoff_abort "composer-pos"
  read -r x y <<<"$pos"
  echo "handoff: композер $x,$y"
  DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
  trace_after click-composer
  sleep 0.2
  # /remote-control на 3.23 сам стартует «Set up environment» (~19–22 с), даже
  # когда чип уже This Computer (BL-003, bc-…). Слэш не кликаем.
  echo "handoff: /remote-control пропускаю (меню чипа RC не содержит)"
  if [ "$trace" = 1 ]; then
    clip_paste "$msg" || exit 1
    trace_after paste-prompt
    sleep 0.3
  elif [ "$dry" = 1 ]; then
    echo "handoff: dry-run, текст первого сообщения не вставляю"
  else
    clip_paste "$msg" || exit 1
    sleep 0.3
  fi

  if [ "$dry" = 1 ]; then
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    trace_after escape-1
    sleep 0.2
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    trace_after escape-2
    sleep 0.3
    if [ "$trace" = 1 ]; then
      local try opened pal
      pal="$VAR/shots/_search-agents.png"
      mkdir -p "$VAR/shots"
      for try in 1 2 3; do
        DISPLAY="$DISP" xdotool key --clearmodifiers ctrl+alt+p
        trace_after "ctrl-alt-p-$try"
        sleep 0.7
        DISPLAY="$DISP" import -window root "$pal" 2>/dev/null || DISPLAY="$DISP" scrot -o "$pal"
        if python3 "$GLASS_AGENTS" palette-open "$pal"; then
          opened=1
          break
        fi
        DISPLAY="$DISP" xdotool key --clearmodifiers Escape
        trace_after "ctrl-alt-p-$try-escape"
        sleep 0.5
      done
      if [ "${opened:-0}" = 1 ] && [ -n "$prev_id" ]; then
        clip_paste "$prev_id"
        trace_after paste-prev-id-into-palette
        sleep 0.5
        DISPLAY="$DISP" import -window root "$pal" 2>/dev/null || DISPLAY="$DISP" scrot -o "$pal"
        if python3 "$GLASS_AGENTS" palette-ok "$pal" "${prev_name:-$prev_id}" "$prev_id"; then
          DISPLAY="$DISP" xdotool key --clearmodifiers Return
          trace_after return-palette
        else
          DISPLAY="$DISP" xdotool key --clearmodifiers Escape
          trace_after palette-ok-fail-escape
        fi
      fi
    elif [ -n "$prev_id" ]; then
      glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" || echo "handoff: dry-run, не вернул вкладку $prev_id" >&2
    fi
    local m_after
    m_after=$(mouse1)
    # Первый dry-run записал sqlite ~19 с после remote-control — добрать хвост.
    if [ "$trace" = 1 ]; then
      local i
      echo "TRACE final-wait 16s после last=${last_trace_step:-?}  $(date +%H:%M:%S)"
      for i in 1 2 3 4; do
        sleep 4
        if python3 "$GLASS_AGENTS" created-since "$t0_ms" >/dev/null 2>&1; then
          trace_hit "final-wait-after-${last_trace_step:-unknown}"
        fi
        echo "TRACE none final-wait $i  $(date +%H:%M:%S)"
      done
    fi
    if python3 "$GLASS_AGENTS" created-since "$t0_ms" >/dev/null 2>&1; then
      if [ "$trace" = 1 ]; then
        trace_hit "after-all-steps"
      fi
      echo "handoff: dry-run, но sqlite дал новую сессию — стоп" >&2
      python3 "$GLASS_AGENTS" created-since "$t0_ms" >&2 || true
      exit 1
    fi
    echo "handoff: dry-run ок, якоря шагов 1–5 найдены, Return не жали, новых сессий нет"
    echo "мышь $ORIG_DISPLAY  до $m_before  после $m_after"
    write_ui_checked
    return 0
  fi

  DISPLAY="$DISP" xdotool key --clearmodifiers Return
  sleep 1

  # 3.23: Return даёт локальный чат (uuid без bc-). RC = конвертация через
  # футер This Computer → Continue on → Self-Hosted Worker (замер 14:28).
  local sel local_uuid i replied rc nid nname ok=0
  local_uuid=""
  for i in $(seq 1 30); do
    sel=$(python3 "$GLASS_AGENTS" selected | head -1)
    if [ -n "$sel" ] && [ "$sel" != "$prev_id" ]; then
      local_uuid=${sel#bc-}
      echo "handoff: локальный чат selected=$sel"
      break
    fi
    sleep 1
  done
  if [ -z "$local_uuid" ]; then
    handoff_shot "handoff-fail-no-local" >/dev/null
    echo "handoff ЗАБЛОКИРОВАН: selectedAgent за 30 с не сменился на новый uuid" >&2
    [ -n "${prev_id:-}" ] && glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" >/dev/null 2>&1 || true
    exit 1
  fi

  # Ждём конец первого ответа (короткий READY): футер + follow-up, без Stop.
  # overlay-scan не каждый тик (дорого); selected не должен уехать с локального uuid.
  replied=0
  for i in $(seq 1 90); do
    sel=$(python3 "$GLASS_AGENTS" selected | head -1)
    if [ "${sel#bc-}" != "$local_uuid" ] && [ "$sel" != "$local_uuid" ] && [ "$sel" != "bc-$local_uuid" ]; then
      echo "handoff: вкладка уехала на '$sel' — возвращаю $local_uuid" >&2
      glass_focus_bcid "$local_uuid" "$local_uuid" >/dev/null 2>&1 \
        || glass_focus_bcid "bc-$local_uuid" "$local_uuid" >/dev/null 2>&1 || true
    fi
    if [ $((i % 5)) -eq 1 ]; then
      shot=$(stand_dismiss_overlays h-reply) || {
        echo "handoff: Move agent while working во время первого ответа — жду" >&2
        sleep 2
        continue
      }
    else
      shot=$(handoff_shot h-reply)
    fi
    # Готовность = футер + follow-up. stop-pos ложно цепляет круглую кнопку
    # у follow-up (fallback Environment) — не использовать здесь.
    if python3 "$GLASS_AGENTS" anchor "$shot" footer-this-computer >/dev/null 2>&1 \
      && python3 "$GLASS_AGENTS" anchor "$shot" send-follow-up >/dev/null 2>&1; then
      if python3 "$GLASS_AGENTS" turn-busy "$shot"; then
        echo "handoff: футер есть, но на экране Planning next moves — жду"
        sleep 1
        continue
      fi
      replied=1
      echo "handoff: первый ответ готов (футер This Computer, follow-up)"
      break
    fi
    sleep 1
  done
  if [ "$replied" != 1 ]; then
    echo "handoff ЗАБЛОКИРОВАН: нет футера This Computer / follow-up за 90 с" >&2
    [ -n "${prev_id:-}" ] && glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" >/dev/null 2>&1 || true
    exit 1
  fi

  if [ "$no_convert" = 1 ]; then
    echo "handoff: --no-convert — локальный чат $local_uuid оставлен без RC"
    echo "дальше: $0 convert --id $local_uuid -w $ws${name:+ -n $name}"
    write_ui_checked
    return 0
  fi

  if ! glass_convert_to_rc "$local_uuid" "$ws"; then
    [ -n "${prev_id:-}" ] && glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" >/dev/null 2>&1 || true
    exit 1
  fi
  ok=1
  if ! python3 "$GLASS_AGENTS" handoff-ok "$ws" "$t0_ms" "$local_uuid"; then
    echo "handoff: ОТКАЗ — convert-ok был, но новейшая с t0 не local-rc $ws" >&2
    ok=0
  fi
  nid="bc-$local_uuid"
  if [ "$ok" -eq 1 ] && [ -n "$name" ]; then
    nname=$(python3 "$GLASS_AGENTS" resolve --id "$nid" | sed -n '2p' || true)
    if glass_focus_bcid "$nid" "${nname:-$name}"; then
      glass_rename "$name" "$nid" || echo "handoff: агент $nid создан, имя '$name' не выставилось" >&2
    else
      echo "handoff: local-rc есть, но не открыл вкладку для имени '$name'" >&2
    fi
  fi
  if [ "$ok" -eq 1 ] && [ -n "$then_msg" ]; then
    echo "handoff: второе сообщение (--then) через composer-send"
    cmd_composer_send --id "$nid" "$then_msg" || {
      echo "handoff: local-rc $nid есть, --then не отправился" >&2
      ok=0
    }
  fi
  local m_after
  m_after=$(mouse1)
  DISPLAY="$DISP" import -window "$wid" "$VAR/shots/handoff-$(date +%H%M%S).png" 2>/dev/null || true
  echo "мышь $ORIG_DISPLAY  до $m_before  после $m_after"
  if [ "$ok" -eq 1 ]; then
    echo "handoff отправлен на $DISP (логин $email, папка $ws${name:+, имя $name})"
    echo "проверь inbox: новая bc-id, не эта сессия. Снимок в $VAR/shots/"
    write_ui_checked
  else
    echo "handoff: ОТКАЗ — сессия не готова (папка $ws${name:+, имя $name}). Снимок в $VAR/shots/" >&2
  fi
  [ "$ok" -eq 1 ]
}

# Папки живых воркеров стенда (значение --worker-dir из cmdline; ключ не читаем).
stand_worker_dirs() {
  local pid
  for pid in $(stand_worker_pids); do
    tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | awk 'p { print; exit } $0 == "--worker-dir" { p = 1 }'
  done | sort -u
}

# Cursor extension запускает private worker как `cursor-agent --api-key <key>`.
# Сам CLI умеет `CURSOR_API_KEY`, поэтому патчим shell-launcher installed-версий:
# ключ остаётся в env дочернего процесса, но исчезает из долгоживущего argv Node.
sanitize_cursor_agent_launchers() {
  local root="$PROFILE/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
  [ -d "$root" ] || return 0
  python3 - "$root" "$HERE/cursor-agent-argv-sanitize.sh" <<'PY'
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1])
block = pathlib.Path(sys.argv[2]).read_text()
if not block.endswith("\n"):
    block += "\n"
marker = "# cursor-stand argv-sanitize: --api-key -> CURSOR_API_KEY"
needle = "\nshould_skip_system_ca() {\n"
for path in sorted(root.glob("*/cursor-agent")):
    try:
        text = path.read_text()
    except UnicodeDecodeError:
        continue
    if marker in text:
        if "не совпадает с --api-key" in text:
            continue
        start = text.find(marker)
        end = text.find("unset SANITIZED_ARGS\n", start)
        if end == -1:
            print(f"sanitize: skip {path}: old block has no end", file=sys.stderr)
            continue
        end += len("unset SANITIZED_ARGS\n")
        path.write_text(text[:start] + block + text[end:])
        path.chmod(stat.S_IMODE(path.stat().st_mode))
        print(f"sanitize: refreshed {path}", file=sys.stderr)
        continue
    if needle not in text:
        print(f"sanitize: skip {path}: marker point not found", file=sys.stderr)
        continue
    backup = path.with_name(path.name + ".before-argv-sanitize-20261010")
    if not backup.exists():
        backup.write_text(text)
        backup.chmod(stat.S_IMODE(path.stat().st_mode))
    path.write_text(text.replace(needle, "\n" + block + needle.lstrip(), 1))
    path.chmod(stat.S_IMODE(path.stat().st_mode))
    print(f"sanitize: patched {path}", file=sys.stderr)
PY
}

# Воркер private worker поднимает сам Cursor стенда, когда открыта вкладка сессии
# этой папки. После перезагрузки он возвращает только последнюю открытую — остальные
# сессии «@ этой машины» видны в вебе, но не продолжаются. Открываем по вкладке на
# папку (самую свежую), ждём воркер. Ключ воркера не трогаем — запускает только Cursor.
cmd_workers() {
  adopt_if_live >/dev/null 2>&1 || load_state || { echo "стенд не поднят" >&2; return 1; }
  [ -n "$(stand_cursor_pids)" ] || { echo "Cursor стенда не запущен" >&2; return 1; }
  sanitize_cursor_agent_launchers
  local host id name ws i missing=0 total=0
  host=$(hostname)
  local kind working
  # mine: id TAB name TAB ws TAB kind TAB working (с a0be7f4). Воркер нужен только
  # local-rc; без разбора kind/working путь не совпадал ни с одним --worker-dir,
  # и ensure перезапускал Cursor стенда (14.10.2026).
  while IFS=$'\t' read -r id name ws kind working; do
    [ -n "$id" ] || continue
    [ "${kind:-local-rc}" = "local-rc" ] || continue
    total=$((total + 1))
    if stand_worker_dirs | grep -qxF "$ws"; then
      echo "воркер есть   $ws"
      continue
    fi
    if [ "${working:-0}" = "1" ]; then
      echo "воркера нет   $ws — сессия работает, вкладку не переключаю ($id)" >&2
      missing=$((missing + 1))
      continue
    fi
    echo "воркера нет   $ws — открываю вкладку '$name' ($id)"
    # Уже выделенная вкладка: повторный фокус ничего не делает — сначала уйти на другую.
    if [ "$(python3 "$GLASS_AGENTS" selected | head -1)" = "$id" ]; then
      local other
      mapfile -t other < <(python3 "$GLASS_AGENTS" other "$id" "$host")
      [ -n "${other[0]:-}" ] && glass_focus_bcid "${other[0]}" "${other[1]:-}" >/dev/null || true
    fi
    if ! glass_focus_bcid "$id" "$name"; then
      echo "  вкладку $id открыть не смог" >&2
      missing=$((missing + 1))
      continue
    fi
    for i in $(seq 24); do
      sleep 5
      stand_worker_dirs | grep -qxF "$ws" && break
    done
    if stand_worker_dirs | grep -qxF "$ws"; then
      echo "  воркер поднят $ws"
    else
      echo "  воркер $ws за 2 мин не появился" >&2
      missing=$((missing + 1))
    fi
  done < <(python3 "$GLASS_AGENTS" mine "$host")
  echo "workers: папок @ $host — $total, без воркера — $missing"
  [ "$missing" -eq 0 ]
}

cmd_ensure() {
  if [ -e "$HOLD" ]; then
    echo "стенд остановлен вручную (park/down, метка $HOLD) — не поднимаю; снять: cursor-stand.sh up"
    return 0
  fi
  local pkg checked
  pkg=$(cursor_pkg_ver || true)
  if [ -f "$VAR/ui-checked" ]; then
    checked=$(tr -d ' \n' < "$VAR/ui-checked")
    if [ -n "$pkg" ] && [ "$pkg" != "$checked" ]; then
      echo "ensure: Cursor обновлён до $pkg, handoff не проверен (ui-checked $checked)"
    fi
  fi
  if ! xdpyinfo -display "$DISP" >/dev/null 2>&1 || [ -z "$(stand_cursor_pids)" ]; then
    echo "ensure: стенд не целый — up"
    cmd_up
    sleep 10
  fi
  cmd_workers && return 0
  # Воркер умер при живом Cursor: Cursor этого не замечает и повторным открытием
  # вкладки его не поднимает (замер 07.10.2026). Поднимает только свежий запуск
  # Cursor стенда — перезапускаем его, но не чаще раза в 30 мин (без метки hold).
  local mark="$VAR/last-restart" now
  now=$(date +%s)
  if [ -e "$mark" ] && [ $((now - $(cat "$mark" 2>/dev/null || echo 0))) -lt 1800 ]; then
    echo "ensure: Cursor стенда перезапускался меньше 30 мин назад — жду следующего тика" >&2
    return 1
  fi
  local busy shot
  mkdir -p "$VAR/shots"
  shot="$VAR/shots/_ensure-busy.png"
  if ! DISPLAY="$DISP" import -window root "$shot" 2>/dev/null; then
    DISPLAY="$DISP" scrot -o "$shot" 2>/dev/null || true
  fi
  if [ -s "$shot" ]; then
    busy=$(python3 "$GLASS_AGENTS" busy "$(hostname)" "$shot" || true)
  else
    busy=$(python3 "$GLASS_AGENTS" busy "$(hostname)" || true)
  fi
  if [ -n "$busy" ]; then
    echo "ensure: на этой машине работает агент — Cursor стенда не перезапускаю: $(cut -f2 <<<"$busy" | paste -sd, -)" >&2
    return 1
  fi
  shot="$VAR/shots/_ensure-busy-2.png"
  if ! DISPLAY="$DISP" import -window root "$shot" 2>/dev/null; then
    DISPLAY="$DISP" scrot -o "$shot" 2>/dev/null || true
  fi
  if ! ensure_idle_now "$shot" "$(hostname)"; then
    echo "ensure: перед остановкой агент уже работает — не убиваю" >&2
    return 1
  fi
  echo "$now" > "$mark"
  echo "ensure: воркеры не поднялись — перезапускаю Cursor стенда (экран и VNC остаются)"
  local pids
  mapfile -t pids < <(stand_cursor_pids; stand_worker_pids)
  [ "${#pids[@]}" -gt 0 ] && kill_pids "${pids[@]}"
  local i
  for i in $(seq 15); do
    sleep 2
    [ -z "$(stand_cursor_pids)" ] && break
  done
  cmd_up
  sleep 10
  cmd_workers
}

# Ждать private worker стенда для папки. Cmdline воркера не печатать (там ключ).
cmd_wait_worker() {
  local ws timeout="${CURSOR_STAND_WAIT_WORKER_SEC:-120}" i
  [ $# -ge 1 ] || { echo "wait-worker: укажи папку проекта" >&2; exit 1; }
  ws=$(resolve_workspace "$1") || exit 1
  adopt_if_live >/dev/null 2>&1 || load_state || true
  for i in $(seq 1 "$timeout"); do
    if stand_worker_dirs | grep -qxF "$ws"; then
      echo "воркер есть  $ws  (${i}s)"
      return 0
    fi
    sleep 1
  done
  echo "wait-worker: за ${timeout}s нет воркера $ws" >&2
  return 1
}

# Повторный send в композер УЖЕ открытой вкладки. Не New Chat.
# Координаты = cmd_handoff (glass 1920×1080 @ 0,0). Опциональный текст — вставка.
cmd_composer_send() {
  # composer-send [--id bc-…] [--dry-run] [текст]
  # Return в поле ввода открытой вкладки glass (resend после worker-not-ready).
  # Поле ищется по снимку (новый чат / переписка), не фиксированной точкой:
  # 960,545 в переписке — середина ленты, текст уходил мимо (07.10.2026).
  local expect="" dry=0 sel shot pos x y
  while [ $# -gt 0 ]; do
    case "$1" in
      --id) expect=${2:-}; shift 2 ;;
      --dry-run) dry=1; shift ;;
      *) break ;;
    esac
  done
  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  export DISPLAY="$DISP"
  agents_window >/dev/null || exit 1
  if [ -n "$expect" ]; then
    local resolved rname
    resolved=$(python3 "$GLASS_AGENTS" resolve --id "$expect") || exit 1
    expect=$(printf '%s\n' "$resolved" | sed -n '1p')
    rname=$(printf '%s\n' "$resolved" | sed -n '2p')
    glass_focus_bcid "$expect" "${rname:-$expect}" || exit 1
    sel=$(python3 "$GLASS_AGENTS" selected | head -1)
    [ "$sel" = "$expect" ] || { echo "composer-send: открыта '$sel', ждали $expect — не отправляю" >&2; exit 1; }
  fi
  mkdir -p "$VAR/shots"
  shot=$(stand_dismiss_overlays _composer) || {
    echo "composer-send: диалог Move agent while working — не отправляю" >&2
    exit 1
  }
  pos=$(python3 "$GLASS_AGENTS" composer-pos "$shot" "$(hostname)") || {
    shot=$(stand_dismiss_overlays _composer2) || true
    pos=$(python3 "$GLASS_AGENTS" composer-pos "$shot" "$(hostname)") || {
      echo "composer-send: не узнал экран (ни новый чат, ни переписка @ $(hostname)) — не кликаю; см. $shot" >&2
      exit 1
    }
  }
  read -r x y <<<"$pos"
  if [ "$dry" = 1 ]; then
    echo "composer-send: поле ввода $x,$y (dry-run, ничего не нажато)"
    return 0
  fi
  DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
  sleep 0.2
  if [ $# -gt 0 ]; then
    clip_paste "$*" || exit 1
    sleep 0.2
  fi
  DISPLAY="$DISP" xdotool key --clearmodifiers Return
  echo "composer-send на $DISP ($x,$y)"
}

cmd_pick_display() {
  echo "display_sh  $STAND_DISPLAY_SH"
  echo "CURSOR_STAND_X  ${CURSOR_STAND_X:-auto}"
  echo -n "pick  "
  stand_pick_xserver
  if xdpyinfo -display "$DISP" >/dev/null 2>&1; then
    local pid cmd
    pid=$(stand_xserver_pid "$DISP" "")
    cmd=$(ps -o args= -p "${pid:-0}" 2>/dev/null | tr -s ' ' | cut -c1-100)
    echo "live  $DISP  pid=${pid:-?}  $cmd"
  else
    echo "live  $DISP  нет"
  fi
}

# Stop выполняющейся сессии (кнопка Stop на открытой вкладке). Не нашу.
glass_stop() {
  local id=$1 expected=$2 shot pos ax ay i sel st
  [ -n "$id" ] || return 1
  case "$ARCHIVE_PROTECTED_IDS" in
    *"$id"*) echo "stop: отказ, защищённая сессия $id" >&2; return 1 ;;
  esac
  glass_focus_bcid "$id" "$expected" || return 1
  sel=$(python3 "$GLASS_AGENTS" selected | head -1)
  if [ "$sel" != "$id" ]; then
    echo "stop: выделена '$sel', ждали $id" >&2
    return 1
  fi
  mkdir -p "$VAR/shots"
  shot="$VAR/shots/_stop.png"
  DISPLAY="$DISP" import -window root "$shot" 2>/dev/null || DISPLAY="$DISP" scrot -o "$shot"
  pos=$(python3 "$GLASS_AGENTS" stop-pos "$shot") || {
    echo "stop: нет кнопки Stop на снимке $shot" >&2
    return 1
  }
  ax=$(printf '%s\n' "$pos" | awk '{print $1}')
  ay=$(printf '%s\n' "$pos" | awk '{print $2}')
  echo "stop: клик $ax,$ay у $id"
  DISPLAY="$DISP" xdotool mousemove --sync "$ax" "$ay" click --clearmodifiers 1
  for i in $(seq 1 40); do
    sleep 0.5
    st=$(python3 "$GLASS_AGENTS" show "$id" | sed -n 's/^status=//p')
    if [ "$st" != "1" ]; then
      echo "stop: status=$st у $id"
      return 0
    fi
  done
  echo "stop: status всё ещё 1 у $id" >&2
  return 1
}

# Защита archive — только из config/hosts/<host>.env.
# Пустые оба списка: archive отказывается до клика (пример env и SETUP).
ARCHIVE_PROTECTED_IDS="${ARCHIVE_PROTECTED_IDS:-}"
ARCHIVE_PROTECTED_NAMES="${ARCHIVE_PROTECTED_NAMES:-}"

archive_protection_ok() {
  local id=$1 name=$2
  if [ -z "$ARCHIVE_PROTECTED_IDS" ] && [ -z "$ARCHIVE_PROTECTED_NAMES" ]; then
    echo "archive: список защиты пуст (ARCHIVE_PROTECTED_IDS и ARCHIVE_PROTECTED_NAMES) — не архивирую" >&2
    return 1
  fi
  case "$ARCHIVE_PROTECTED_IDS" in
    *"$id"*) echo "archive: отказ, защищённая сессия $id ($name)" >&2; return 1 ;;
  esac
  if [ -n "$ARCHIVE_PROTECTED_NAMES" ] && printf '%s\n' "$name" | grep -Eqx "$ARCHIVE_PROTECTED_NAMES"; then
    echo "archive: отказ, защищённое имя '$name' ($id)" >&2
    return 1
  fi
  return 0
}

# 0 — прямо сейчас никого нет. Печатает строки busy и возвращает 1, если кто-то работает.
ensure_idle_now() {
  local shot=$1 host=$2 busy="" rc=0
  if [ -n "$shot" ] && [ -s "$shot" ]; then
    busy=$(python3 "$GLASS_AGENTS" busy "$host" "$shot") || rc=$?
  else
    busy=$(python3 "$GLASS_AGENTS" busy "$host") || rc=$?
  fi
  # Сбой чтения — не «никого нет»: иначе ensure убьёт Cursor вслепую.
  if [ "$rc" != 0 ] || [ -n "$busy" ]; then
    printf '%s\n' "$busy"
    return 1
  fi
  return 0
}

# archive --id bc-…: меню сайдбара → Archive. Не «Archive All Below».
cmd_archive() {
  [ "${1:-}" = "--id" ] && [ -n "${2:-}" ] || { echo "archive: нужен --id bc-…" >&2; exit 1; }
  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  export DISPLAY="$DISP"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS
  local resolved id name ws
  resolved=$(python3 "$GLASS_AGENTS" resolve --id "$2") || exit 1
  id=$(printf '%s\n' "$resolved" | sed -n '1p')
  name=$(printf '%s\n' "$resolved" | sed -n '2p')
  ws=$(printf '%s\n' "$resolved" | sed -n '3p')
  local show st
  show=$(python3 "$GLASS_AGENTS" show "$id") || exit 1
  st=$(printf '%s\n' "$show" | sed -n 's/^status=//p')
  if [ "$st" = "1" ]; then
    echo "archive: отказ, сессия выполняется (status=1) $id ($name)" >&2
    exit 1
  fi
  archive_protection_ok "$id" "$name" || exit 1
  printf '%s\n' "$show"
  if python3 "$GLASS_AGENTS" is-archived "$id" >/dev/null; then
    echo "уже в архиве $id ($name)"
    return 0
  fi
  local m_before m_after y shot pos ax ay i sel
  m_before=$(mouse1)
  glass_focus_bcid "$id" "$name" || exit 1
  sel=$(python3 "$GLASS_AGENTS" selected | head -1)
  if [ "$sel" != "$id" ]; then
    echo "archive: выделена '$sel', ждали $id — не архивирую" >&2
    exit 1
  fi
  agents_window >/dev/null || exit 1
  y=$(sidebar_selected_y) || { echo "archive: нет выделенной строки в сайдбаре" >&2; exit 1; }
  if [ "$y" -lt 130 ]; then
    echo "archive: выделено New Chat, не сессия (y=$y)" >&2
    exit 1
  fi
  python3 "$GLASS_AGENTS" row-name "$VAR/shots/_sidebar.png" "$y" "$name" || {
    echo "archive: строка y=$y не совпала с именем — не архивирую" >&2
    exit 1
  }
  DISPLAY="$DISP" xdotool mousemove --sync 120 "$y"
  sleep 0.15
  DISPLAY="$DISP" xdotool click --clearmodifiers 3
  sleep 0.5
  mkdir -p "$VAR/shots"
  shot="$VAR/shots/_archive-menu.png"
  DISPLAY="$DISP" import -window root "$shot" 2>/dev/null || DISPLAY="$DISP" scrot -o "$shot"
  pos=$(python3 "$GLASS_AGENTS" archive-pos "$shot") || {
    DISPLAY="$DISP" xdotool key --clearmodifiers Escape
    echo "archive: в меню нет пункта Archive (не Archive All Below). Снимок $shot" >&2
    exit 1
  }
  ax=$(printf '%s\n' "$pos" | awk '{print $1}')
  ay=$(printf '%s\n' "$pos" | awk '{print $2}')
  DISPLAY="$DISP" xdotool mousemove --sync "$ax" "$ay" click --clearmodifiers 1
  # is-archived печатает true/false. Потолок тот же, что у rename.
  if poll_stdout_eq "$SQLITE_UI_WAIT_SEC" true \
      python3 "$GLASS_AGENTS" is-archived "$id" >/dev/null; then
    m_after=$(mouse1)
    echo "в архиве $id ($name, ws=${ws:-?})"
    echo "мышь $ORIG_DISPLAY  до $m_before  после $m_after"
    return 0
  fi
  DISPLAY="$DISP" xdotool key --clearmodifiers Escape
  echo "archive: клик был, sqlite isArchived всё ещё false у $id (ждали ${SQLITE_UI_WAIT_SEC} с)" >&2
  exit 1
}

# focus --id bc-…: открыть вкладку сессии (Search Agents, с проверкой палитры и sqlite).
cmd_focus() {
  [ "${1:-}" = "--id" ] && [ -n "${2:-}" ] || { echo "focus: нужен --id bc-…" >&2; exit 1; }
  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  local r
  mapfile -t r < <(python3 "$GLASS_AGENTS" resolve --id "$2")
  [ -n "${r[0]:-}" ] || { echo "focus: нет сессии $2" >&2; exit 1; }
  glass_focus_bcid "${r[0]}" "${r[1]:-}"
}

# --- MCP (Customize → MCPs) ----------------------------------------------------
# Не пишет токены. Добавление — правка mcp.json + enable в UI (не форма New MCP Server).

mcp_shot() {
  local out="$VAR/shots/${1:-mcp}-$(date +%H%M%S).png"
  mkdir -p "$VAR/shots"
  DISPLAY="$DISP" import -window root "$out" 2>/dev/null || DISPLAY="$DISP" scrot -o "$out"
  printf '%s\n' "$out"
}

mcp_click_xy() {
  local x=$1 y=$2
  DISPLAY="$DISP" xdotool mousemove --sync "$x" "$y" click --clearmodifiers 1
}

mcp_selected_workspace() {
  local id ws
  id=$(python3 "$GLASS_AGENTS" selected | head -1)
  [ -n "$id" ] || return 0
  ws=$(python3 "$GLASS_AGENTS" show "$id" 2>/dev/null | sed -n "s/^workspaceRootPath='\\(.*\\)'/\\1/p")
  case "$ws" in
    ''|/workspace) return 0 ;;
  esac
  [ -d "$ws" ] && printf '%s\n' "$ws"
}

mcp_known_csv() {
  # Имена из user + project workspace (OCR mt5↔mts): явный -w, иначе selected.
  local ws=${1:-} names
  [ -n "$ws" ] || ws=$(mcp_selected_workspace || true)
  names=$(
    CURSOR_STAND_MCP_WORKSPACE="${ws:-}" python3 - <<'PY'
import json, os
from pathlib import Path
seen, out = set(), []
paths = [Path.home() / ".cursor" / "mcp.json"]
ws = os.environ.get("CURSOR_STAND_MCP_WORKSPACE") or ""
if ws:
    paths += [Path(ws) / ".cursor" / "mcp.json", Path(ws) / ".mcp.json"]
for p in paths:
    if not p.is_file():
        continue
    try:
        raw = json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        continue
    servers = raw.get("mcpServers") if isinstance(raw, dict) else None
    if not isinstance(servers, dict):
        continue
    for n in servers:
        if n not in seen:
            seen.add(n)
            out.append(str(n))
print(",".join(out))
PY
  )
  printf '%s\n' "$names"
}

# Открыть Customize → вкладка MCPs. Возвращает путь снимка списка.
# Поиск Customize search не используем: вставка имени уводит с вкладок (замер 07.10).
mcp_open_panel() {
  local shot pos x y
  agents_window >/dev/null || return 1
  # Убрать курсор с сайдбара (подсветка hover ломает OCR списка).
  DISPLAY="$DISP" xdotool mousemove --sync 960 420
  sleep 0.2
  shot=$(mcp_shot mcp-before)
  # Уже на вкладке MCPs — не кликать Customize (повтор закрывает панель).
  if python3 "$GLASS_AGENTS" anchor "$shot" customize-mcps >/dev/null 2>&1 \
    && python3 "$GLASS_AGENTS" mcp-list "$shot" >/dev/null 2>&1; then
    printf '%s\n' "$shot"
    return 0
  fi
  # Customize открыт, но не MCPs — только вкладка.
  if python3 "$GLASS_AGENTS" anchor "$shot" customize-mcps >/dev/null 2>&1 \
    || python3 "$GLASS_AGENTS" anchor "$shot" customize-search >/dev/null 2>&1; then
    :
  else
    pos=$(python3 "$GLASS_AGENTS" anchor "$shot" customize) || {
      echo "mcp: нет якоря Customize" >&2
      return 1
    }
    read -r x y <<<"$pos"
    mcp_click_xy "$x" "$y"
    sleep 1.0
    shot=$(mcp_shot mcp-tabs)
  fi
  pos=$(python3 "$GLASS_AGENTS" anchor "$shot" customize-mcps) || {
    echo "mcp: нет вкладки MCPs (Customize открыт? снимок $shot)" >&2
    return 1
  }
  read -r x y <<<"$pos"
  mcp_click_xy "$x" "$y"
  sleep 1.2
  mcp_shot mcp-list
}

mcp_leave_panel() {
  local prev_id=$1 prev_name=$2
  DISPLAY="$DISP" xdotool key --clearmodifiers Escape
  sleep 0.2
  DISPLAY="$DISP" xdotool key --clearmodifiers Escape
  sleep 0.3
  DISPLAY="$DISP" xdotool mousemove --sync 960 420
  if [ -n "$prev_id" ]; then
    glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" >/dev/null 2>&1 || true
  fi
}

mcp_set_enabled() {
  # mcp_set_enabled NAME want(on|off) [workspace_for_known]
  local name=$1 want=$2 ws=${3:-} shot list known pos x y state tx ty i detail
  known=$(mcp_known_csv "$ws")
  [ -n "$known" ] || known="$name"
  case ",$known," in
    *",$name,"*) ;;
    *) known="${known:+$known,}$name" ;;
  esac
  shot=$(mcp_open_panel) || return 1
  list=$(python3 "$GLASS_AGENTS" mcp-list "$shot" "$known") || {
    echo "mcp: список MCPs пуст или OCR не разобрал (снимок $shot)" >&2
    return 1
  }
  pos=$(python3 "$GLASS_AGENTS" mcp-row-pos "$shot" "$name" "$known") || {
    echo "mcp: сервер '$name' не найден во вкладке MCPs" >&2
    printf '%s\n' "$list" >&2
    return 1
  }
  read -r x y <<<"$pos"
  mcp_click_xy "$x" "$y"
  sleep 1.0
  shot=$(mcp_shot mcp-cfg)
  for i in 1 2 3; do
    read -r state tx ty < <(python3 "$GLASS_AGENTS" mcp-toggle "$shot") || {
      echo "mcp: нет тоггла источника в Configure $name (снимок $shot)" >&2
      return 1
    }
    if [ "$state" = "$want" ]; then
      break
    fi
    mcp_click_xy "$tx" "$ty"
    sleep 0.8
    shot=$(mcp_shot mcp-cfg)
    read -r state tx ty < <(python3 "$GLASS_AGENTS" mcp-toggle "$shot") || true
    if [ "$state" = "$want" ]; then
      break
    fi
  done
  if [ "$state" != "$want" ]; then
    echo "mcp: не удалось выставить $name → $want (сейчас ${state:-?})" >&2
    return 1
  fi
  pos=$(python3 "$GLASS_AGENTS" mcp-done-pos "$shot") || {
    echo "mcp: нет кнопки Done" >&2
    return 1
  }
  read -r x y <<<"$pos"
  mcp_click_xy "$x" "$y"
  sleep 1.2
  shot=$(mcp_shot mcp-after)
  detail=$(python3 "$GLASS_AGENTS" mcp-list "$shot" "$known" | awk -F'\t' -v n="$name" 'tolower($1)==tolower(n){print $2"\t"$3; exit}')
  echo "mcp $name → $want  ${detail:-ok}  shot=$shot"
  [ -n "$detail" ]
}

# Settings → Agents. Только чтение: тумблеры не кликаются.
# Запрещённые точки (Cloud Agents, Docs, Unregister, Log Out, Manage, Build on App)
# отсекает settings-pos. Поиск настроек не фокусируем.
settings_chrome_ids() {
  DISPLAY="$DISP" xdotool search --name "Google Chrome" 2>/dev/null || true
}

settings_leave() {
  local prev_id=$1 prev_name=$2 shot pos x y
  shot=$(mcp_shot settings-leave)
  local try
  for try in 1 2; do
    if ! python3 "$GLASS_AGENTS" settings-pos "$shot" page >/dev/null 2>&1; then
      break
    fi
    pos=$(python3 "$GLASS_AGENTS" settings-pos "$shot" back) || break
    read -r x y <<<"$pos"
    mcp_click_xy "$x" "$y"
    sleep 1.2
    shot=$(mcp_shot settings-after)
  done
  DISPLAY="$DISP" xdotool key --clearmodifiers Escape
  sleep 0.3
  shot=$(mcp_shot settings-after)
  if python3 "$GLASS_AGENTS" settings-pos "$shot" page >/dev/null 2>&1; then
    echo "settings: страница не закрылась — в поиск ничего не ввожу" >&2
    return 1
  fi
  DISPLAY="$DISP" xdotool mousemove --sync 960 420
  if [ -n "$prev_id" ]; then
    glass_focus_bcid "$prev_id" "${prev_name:-$prev_id}" >/dev/null 2>&1 || true
  fi
}

settings_open_agents() {
  local shot pos x y
  agents_window >/dev/null || return 1
  DISPLAY="$DISP" xdotool mousemove --sync 960 420
  sleep 0.2
  shot=$(mcp_shot settings-before)
  if ! python3 "$GLASS_AGENTS" settings-pos "$shot" page >/dev/null 2>&1; then
    pos=$(python3 "$GLASS_AGENTS" settings-pos "$shot" file) || {
      echo "settings: нет меню File (снимок $shot)" >&2
      return 1
    }
    read -r x y <<<"$pos"
    mcp_click_xy "$x" "$y"
    sleep 0.45
    shot=$(mcp_shot settings-menu)
    pos=$(python3 "$GLASS_AGENTS" settings-pos "$shot" settings-item) || {
      echo "settings: меню File не то (нет Settings+Exit или это меню проекта). Снимок $shot" >&2
      DISPLAY="$DISP" xdotool key --clearmodifiers Escape
      return 1
    }
    read -r x y <<<"$pos"
    mcp_click_xy "$x" "$y"
    sleep 0.7
    shot=$(mcp_shot settings-page)
    python3 "$GLASS_AGENTS" settings-pos "$shot" page >/dev/null 2>&1 || {
      echo "settings: после клика Settings страница не открылась (снимок $shot)" >&2
      return 1
    }
  fi
  pos=$(python3 "$GLASS_AGENTS" settings-pos "$shot" agents-nav) || {
    echo "settings: нет безопасной строки Agents (Cloud Agents и карточка Build не кликаются). Снимок $shot" >&2
    return 1
  }
  read -r x y <<<"$pos"
  mcp_click_xy "$x" "$y"
  sleep 0.45
}

cmd_settings() {
  local sub=${1:-}
  case "$sub" in
    agents) ;;
    *)
      echo "settings: нужен agents — чтение Settings → Agents, без переключения тумблеров" >&2
      exit 1 ;;
  esac
  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  export DISPLAY="$DISP"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS

  local prev_id prev_name m_before m_after chrome_before chrome_after
  prev_id=$(python3 "$GLASS_AGENTS" selected | head -1)
  prev_name=""
  if [ -n "$prev_id" ]; then
    prev_name=$(python3 "$GLASS_AGENTS" resolve --id "$prev_id" 2>/dev/null | sed -n '2p' || true)
  fi
  m_before=$(mouse1)
  chrome_before=$(settings_chrome_ids | tr '\n' ' ')

  local rc=0 shots=() shot i
  if ! settings_open_agents; then
    rc=1
  else
    DISPLAY="$DISP" xdotool mousemove --sync 1100 520
    for i in 1 2 3 4 5 6 7 8; do
      DISPLAY="$DISP" xdotool click --clearmodifiers 4
    done
    sleep 0.3
    for i in 1 2 3 4 5 6; do
      shot=$(mcp_shot settings-agents)
      shots+=("$shot")
      if python3 "$GLASS_AGENTS" agents-settings-bottom "$shot"; then
        break
      fi
      DISPLAY="$DISP" xdotool mousemove --sync 1100 520
      DISPLAY="$DISP" xdotool click --clearmodifiers 5 click --clearmodifiers 5 \
        click --clearmodifiers 5 click --clearmodifiers 5
      sleep 0.35
    done
    python3 "$GLASS_AGENTS" agents-settings "${shots[@]}" || rc=$?
    printf 'settings shots:'
    printf ' %s' "${shots[@]}"
    printf '\n'
  fi
  settings_leave "$prev_id" "$prev_name" || rc=1
  chrome_after=$(settings_chrome_ids | tr '\n' ' ')
  local id chrome_new=0
  for id in $chrome_after; do
    case " $chrome_before " in
      *" $id "*) ;;
      *)
        DISPLAY="$DISP" xdotool windowclose "$id"
        chrome_new=1 ;;
    esac
  done
  if [ "$chrome_new" = 1 ]; then
    echo "settings: открылся Chrome — окно закрыто, отчёт недостоверен" >&2
    rc=1
  fi
  m_after=$(mouse1)
  echo "мышь $ORIG_DISPLAY  до $m_before  после $m_after"
  return "$rc"
}

cmd_mcp() {
  local sub=${1:-}
  shift || true
  adopt_if_live || load_state || { echo "стенд не поднят — сначала up" >&2; exit 1; }
  export DISPLAY="$DISP"
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && export DBUS_SESSION_BUS_ADDRESS

  local prev_id prev_name m_before m_after
  prev_id=$(python3 "$GLASS_AGENTS" selected | head -1)
  prev_name=""
  if [ -n "$prev_id" ]; then
    prev_name=$(python3 "$GLASS_AGENTS" resolve --id "$prev_id" 2>/dev/null | sed -n '2p' || true)
  fi
  m_before=$(mouse1)

  case "$sub" in
    list|find|enable|disable|add) ;;
    *)
      echo "mcp: нужен list|find|enable|disable|add" >&2
      echo "  $0 mcp list" >&2
      echo "  $0 mcp find NAME" >&2
      echo "  $0 mcp enable NAME" >&2
      echo "  $0 mcp disable NAME" >&2
      echo "  $0 mcp add -w /ABS -n NAME --command /path [--arg …]" >&2
      echo "  $0 mcp add --user -n NAME --command /path" >&2
      exit 1 ;;
  esac

  local rc=0
  case "$sub" in
    list)
      local shot known
      known=$(mcp_known_csv)
      shot=$(mcp_open_panel) || rc=1
      if [ "$rc" = 0 ] && ! python3 "$GLASS_AGENTS" mcp-list "$shot" "$known"; then
        echo "mcp list: OCR не нашёл серверов (снимок $shot)" >&2
        rc=1
      fi
      mcp_leave_panel "$prev_id" "$prev_name"
      ;;
    find)
      local name=${1:-} shot known line
      [ -n "$name" ] || { echo "mcp find: укажи имя" >&2; exit 1; }
      known=$(mcp_known_csv)
      case ",$known," in *",$name,"*) ;; *) known="${known:+$known,}$name" ;; esac
      shot=$(mcp_open_panel) || rc=1
      if [ "$rc" = 0 ]; then
        line=$(python3 "$GLASS_AGENTS" mcp-list "$shot" "$known" | awk -F'\t' -v n="$name" 'tolower($1)==tolower(n){print; exit}')
      fi
      mcp_leave_panel "$prev_id" "$prev_name"
      if [ -n "$line" ]; then
        printf '%s\n' "$line"
      else
        echo "mcp find: '$name' нет во вкладке MCPs" >&2
        rc=1
      fi
      ;;
    enable|disable)
      local name=${1:-} want
      [ -n "$name" ] || { echo "mcp $sub: укажи имя" >&2; exit 1; }
      want=on
      [ "$sub" = disable ] && want=off
      mcp_set_enabled "$name" "$want" || rc=$?
      mcp_leave_panel "$prev_id" "$prev_name"
      ;;
    add)
      local ws="" user=0 name="" command="" url="" args=()
      while [ $# -gt 0 ]; do
        case "$1" in
          -w|--workspace)
            [ $# -ge 2 ] || { echo "mcp add: $1 ждёт путь" >&2; exit 1; }
            ws=$2; shift 2 ;;
          --workspace=*) ws=${1#--workspace=}; shift ;;
          --user) user=1; shift ;;
          -n|--name)
            [ $# -ge 2 ] || { echo "mcp add: $1 ждёт имя" >&2; exit 1; }
            name=$2; shift 2 ;;
          --name=*) name=${1#--name=}; shift ;;
          --command)
            [ $# -ge 2 ] || { echo "mcp add: --command ждёт путь" >&2; exit 1; }
            command=$2; shift 2 ;;
          --command=*) command=${1#--command=}; shift ;;
          --url)
            [ $# -ge 2 ] || { echo "mcp add: --url ждёт URL" >&2; exit 1; }
            url=$2; shift 2 ;;
          --url=*) url=${1#--url=}; shift ;;
          --arg)
            [ $# -ge 2 ] || { echo "mcp add: --arg ждёт значение" >&2; exit 1; }
            args+=("$2"); shift 2 ;;
          -*) echo "mcp add: неизвестный флаг $1" >&2; exit 1 ;;
          *) echo "mcp add: лишний аргумент $1" >&2; exit 1 ;;
        esac
      done
      [ -n "$name" ] || { echo "mcp add: нужен -n NAME" >&2; exit 1; }
      if [ -z "$command" ] && [ -z "$url" ]; then
        echo "mcp add: нужен --command или --url" >&2
        exit 1
      fi
      local target
      if [ "$user" = 1 ]; then
        target="$HOME/.cursor/mcp.json"
      else
        [ -n "$ws" ] || { echo "mcp add: укажи -w /ABS/PROJECT или --user" >&2; exit 1; }
        ws=$(resolve_workspace "$ws") || exit 1
        target="$ws/.cursor/mcp.json"
      fi
      local merge=(python3 "$GLASS_AGENTS" mcp-merge-json "$target" "$name")
      if [ -n "$url" ]; then
        merge+=(--url "$url")
      else
        merge+=(--command "$command")
        local a
        for a in "${args[@]+"${args[@]}"}"; do
          merge+=(--arg "$a")
        done
      fi
      "${merge[@]}"
      echo "mcp add: записан $target (сервер $name)"
      # После записи файла UI может ещё не знать сервер — Reload в карточке после enable.
      if mcp_set_enabled "$name" on "$ws"; then
        rc=0
      else
        echo "mcp add: файл есть, но enable в UI не подтвердился — открой Customize → MCPs вручную" >&2
        rc=1
      fi
      mcp_leave_panel "$prev_id" "$prev_name"
      ;;
  esac

  m_after=$(mouse1)
  echo "мышь $ORIG_DISPLAY  до $m_before  после $m_after"
  return "$rc"
}

usage() {
  sed -n '2,49p' "$0" | sed 's/^# \{0,1\}//'
}

case "$CMD" in
  up|workers|handoff|convert|rename|composer-send|mcp|settings|archive|focus|park|down|down-display)
    if [ "$locked" != 1 ]; then
      mkdir -p "$VAR"
      exec flock -o -w 900 "$VAR/.lock" "$0" --locked "$CMD" "$@"
    fi ;;
  ensure)
    if [ "$locked" != 1 ]; then
      mkdir -p "$VAR"
      # flock -o закрывает fd замка перед exec: иначе его наследуют Cursor,
      # x11vnc, openbox и xclip, поднятые этим прогоном, и держат замок вечно
      # иначе следующий тик таймера видит «занято» вечно.
      # -E 75: занятый замок отличим от отказа самого ensure.
      rc=0
      flock -n -o -E 75 "$VAR/.lock" "$0" --locked "$CMD" "$@" || rc=$?
      [ "$rc" = 75 ] && { echo "ensure: занято, пропускаю тик"; exit 0; }
      exit "$rc"
    fi ;;
esac

case "$CMD" in
  status) cmd_status ;;
  up) cmd_up ;;
  workers) cmd_workers ;;
  ensure) cmd_ensure ;;
  shot) cmd_shot ;;
  park) cmd_park ;;
  down) cmd_down ;;
  down-display) cmd_down_display ;;
  handoff) cmd_handoff "$@" ;;
  convert) cmd_convert "$@" ;;
  rename) cmd_rename "$@" ;;
  focus) cmd_focus "$@" ;;
  archive) cmd_archive "$@" ;;
  mcp) cmd_mcp "$@" ;;
  settings) cmd_settings "$@" ;;
  wait-worker) cmd_wait_worker "$@" ;;
  composer-send) cmd_composer_send "$@" ;;
  pick-display) cmd_pick_display "$@" ;;
  -h|--help|help) usage ;;
  *) echo "неизвестная команда '$CMD'" >&2; usage >&2; exit 1 ;;
esac
