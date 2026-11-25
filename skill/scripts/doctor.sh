#!/usr/bin/env bash
# Preflight хоста. Экран не поднимает, cmdline воркера не печатает.
# Свободный живой стенд: handoff --dry-run (клики по новому чату, без Return
# и без текста). Занятый стенд не кликает.
set -euo pipefail
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1" >&2; fail=1; }
warn() { printf 'warn %s\n' "$1" >&2; }

echo "хост $(hostname)  user $(id -un)  skill $CURSOR_STAND_SKILL"

if SH_PATH="$(cursor_stand_resolve_sh)"; then
  ok "скрипт $SH_PATH"
  for cmd in status up handoff convert rename shot; do
    if cursor_stand_has_cmd "$SH_PATH" "$cmd"; then
      ok "команда $cmd"
    else
      bad "в скрипте нет обязательной команды $cmd"
    fi
  done
  for cmd in wait-worker composer-send pick-display mcp; do
    if cursor_stand_has_cmd "$SH_PATH" "$cmd"; then
      ok "команда $cmd"
    else
      warn "в скрипте нет $cmd — fallback scripts/${cmd}.sh"
    fi
  done
  if GLASS_CHK="$(cursor_stand_resolve_glass 2>/dev/null)" && grep -q 'mcp-list' "$GLASS_CHK"; then
    ok "glass mcp-list/mcp-toggle"
  else
    warn "glass_agents без mcp-list — enable MCP из скрипта недоступен"
  fi
  if [ -n "${GLASS_CHK:-}" ] && grep -q 'overlay-scan' "$GLASS_CHK"; then
    ok "glass overlay-scan (expensive-processes / move-working)"
  else
    warn "glass_agents без overlay-scan — toast/диалог Move могут ломать якоря"
  fi
  if grep -q 'write_ui_checked' "$SH_PATH"; then
    ok "handoff пишет ui-checked после dry-run"
  else
    warn "скрипт без write_ui_checked — status не узнает, что якоря проверены"
  fi
else
  bad "нет cursor-stand.sh (CURSOR_STAND_SH= или automation/ в репо)"
fi

if GLASS="$(cursor_stand_resolve_glass 2>/dev/null)"; then
  ok "glass_agents $GLASS"
  glass_usage=$(python3 "$GLASS" 2>&1 || true)
  for gcmd in show created-since handoff-ok overlay-scan; do
    if printf '%s\n' "$glass_usage" | grep -qw "$gcmd"; then
      ok "glass $gcmd"
    else
      bad "в glass_agents.py нет $gcmd — Environment не отличить от local-rc / оверлеи"
    fi
  done
else
  bad "нет glass_agents.py"
fi

if DISP_SH="$(cursor_stand_resolve_display_sh 2>/dev/null)"; then
  ok "экран-скрипт $DISP_SH"
else
  bad "нет stand-display.sh"
fi

for bin in xdotool xclip python3 tesseract Xorg Xvfb openbox x11vnc; do
  if command -v "$bin" >/dev/null 2>&1; then
    ok "$bin"
  else
    case "$bin" in
      Xvfb) warn "нет Xvfb — auto не сможет откатиться с GPU" ;;
      Xorg) bad "нет Xorg — GPU-ветка невозможна" ;;
      openbox|x11vnc) warn "нет $bin — up может не довести glass/VNC" ;;
      *) bad "нет $bin" ;;
    esac
  fi
done

if command -v import >/dev/null 2>&1 || command -v scrot >/dev/null 2>&1; then
  ok "снимок ($(command -v import 2>/dev/null || true) $(command -v scrot 2>/dev/null || true))"
else
  bad "нет ImageMagick import и scrot"
fi

if python3 -c 'from PIL import Image' 2>/dev/null; then
  ok "python3 Pillow"
else
  bad "нет Pillow (python3-pil) — OCR палитры Search Agents не сработает"
fi

if tesseract --list-langs 2>/dev/null | grep -qx eng \
  && tesseract --list-langs 2>/dev/null | grep -qx rus; then
  ok "tesseract langs eng+rus"
else
  warn "tesseract без eng+rus — rename целься --id"
fi

PROXY_BIN="${CURSOR_STAND_BIN:-/usr/local/bin/cursor-proxy}"
if [ -x "$PROXY_BIN" ]; then
  ok "бинарь $PROXY_BIN"
else
  bad "нет $PROXY_BIN — up не стартует Cursor стенда"
fi

DRV="${CURSOR_STAND_NVIDIA_DRV:-/usr/lib/x86_64-linux-gnu/nvidia/xorg/nvidia_drv.so}"
if [ -f "$DRV" ]; then
  ok "nvidia_drv $DRV"
else
  warn "нет $DRV — auto уйдёт в Xvfb"
fi

WRAP="${CURSKILL_XORG:-/usr/local/sbin/curskill-xorg}"
if [ -x "$WRAP" ]; then
  ok "обёртка Xorg $WRAP"
  if sudo -n -l -- "$WRAP" >/dev/null 2>&1; then
    ok "NOPASSWD $WRAP"
  else
    warn "нет NOPASSWD на $WRAP"
  fi
elif sudo -n true 2>/dev/null; then
  ok "sudo -n true (Xorg стенда через sudo)"
else
  warn "нет passwordless sudo на Xorg — auto → Xvfb или up падает"
fi

echo "CURSOR_STAND_X=${CURSOR_STAND_X:-auto}"
if [ -n "${DISP_SH:-}" ]; then
  # shellcheck disable=SC1090
  PICK=$(
    set +e
    # shellcheck disable=SC1090
    . "$DISP_SH"
    stand_pick_xserver
  )
  echo "pick  ${PICK:-?}"
fi

DISP="${CURSOR_STAND_DISPLAY:-:105}"
if xdpyinfo -display "$DISP" >/dev/null 2>&1; then
  num="${DISP#:}"
  pid=$(tr -d ' \n' < "/tmp/.X${num}-lock" 2>/dev/null || true)
  args=$(ps -o args= -p "${pid:-0}" 2>/dev/null | tr -s ' ' | cut -c1-90)
  ok "DISPLAY $DISP жив pid=${pid:-?} $args"
else
  warn "DISPLAY $DISP не отвечает — нужен stand.sh up (не если у монитора этой GPU человек)"
fi

PROFILE="$(cursor_stand_profile)"
if [ -d "$PROFILE" ]; then
  ok "профиль $PROFILE"
else
  warn "нет профиля $PROFILE — появится на up"
fi
if [ -e "$PROFILE/var/hold" ]; then
  warn "hold $PROFILE/var/hold — ensure/таймер не поднимут; снять: stand.sh up"
fi

ORIG="${CURSOR_STAND_ORIG_DISPLAY:-:1}"
if DISPLAY="$ORIG" xdotool getmouselocation >/dev/null 2>&1; then
  loc=$(DISPLAY="$ORIG" xdotool getmouselocation)
  ok "мышь стола $ORIG $loc"
else
  warn "мышь стола $ORIG unavailable — изоляцию стола не измерить (само по себе не запрет)"
fi

# Порт, который реально возьмёт стенд: CURSOR_STAND_PROXY или дефолт скрипта хоста.
PROXY_URL="${CURSOR_STAND_PROXY:-}"
if [ -z "$PROXY_URL" ] && [ -n "${SH_PATH:-}" ]; then
  PROXY_URL=$(sed -n 's/^PROXY_HTTP="\${CURSOR_STAND_PROXY:-\(.*\)}"$/\1/p' "$SH_PATH" | head -1)
fi
if [ -n "$PROXY_URL" ]; then
  pport="${PROXY_URL##*:}"
  if ss -ltn 2>/dev/null | grep -qE ":${pport}( |$)"; then
    ok "proxy стенда $PROXY_URL слушает"
  else
    bad "proxy стенда $PROXY_URL не слушает — up откажется"
  fi
else
  ok "прокси не задан — up не требует порт"
fi

# Якоря, не номер версии. Запрет HANDOFF_FORCE снят (BL-007).
VER="$(cursor_stand_pkg_ver)"
PROFILE="$(cursor_stand_profile)"
checked=""
[ -f "$PROFILE/var/ui-checked" ] && checked=$(tr -d ' \n' < "$PROFILE/var/ui-checked")
if [ -n "$VER" ]; then
  ok "Cursor $VER"
else
  warn "не прочитал версию пакета Cursor"
fi
if [ -n "$checked" ] && [ -n "$VER" ] && [ "$checked" != "$VER" ]; then
  warn "Cursor обновлён до $VER, handoff не проверен (ui-checked $checked)"
fi

handoff_line=""
if [ -n "${GLASS:-}" ] && python3 "$GLASS" busy "$(hostname)" >/dev/null 2>&1; then
  if [ -n "$checked" ] && [ "$checked" = "$VER" ]; then
    handoff_line="handoff: якоря найдены"
    ok "стенд занят — dry-run не гонял, ui-checked=$checked"
  else
    warn "стенд занят — handoff --dry-run не гонял"
    handoff_line="handoff: стенд занят, якоря не проверены этим doctor"
  fi
elif [ -n "${SH_PATH:-}" ] && xdpyinfo -display "${CURSOR_STAND_DISPLAY:-:105}" >/dev/null 2>&1; then
  doc_ws="$(cd "$(dirname "$0")/../.." && pwd)"
  echo "doctor: стенд свободен — handoff --dry-run (клики, без Return и без текста)"
  if "$SH_PATH" handoff --dry-run -w "$doc_ws" >/tmp/cursor-stand-doctor-handoff.log 2>&1; then
    handoff_line="handoff: якоря найдены"
    ok "handoff --dry-run"
  else
    handoff_line="handoff ЗАБЛОКИРОВАН: см. /tmp/cursor-stand-doctor-handoff.log"
    bad "handoff --dry-run"
  fi
else
  warn "стенд не жив — handoff --dry-run не гонял"
  handoff_line="handoff: стенд не жив"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "doctor: хост не готов" >&2
  echo "$handoff_line"
  exit 1
fi
echo "$handoff_line"
echo "doctor: можно status / handoff"
exit 0
