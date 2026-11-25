#!/usr/bin/env bash
# Экран стенда Cursor. Дефолт, если CURSOR_STAND_DISPLAY_SH не задан.
# Обёртка Xorg (CURSKILL_XORG, иначе /usr/local/sbin/curskill-xorg)
# переписывает BusID из lspci. Нет обёртки и нет NOPASSWD — auto уходит в Xvfb.
#
# Файл только подключается (`source`), сам ничего не делает.

STAND_X="${CURSOR_STAND_X:-auto}"
STAND_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAND_XORG_CONF="$STAND_SCRIPTS_DIR/xorg-nvidia-headless.conf"
STAND_NVIDIA_DRV="${CURSOR_STAND_NVIDIA_DRV:-/usr/lib/x86_64-linux-gnu/nvidia/xorg/nvidia_drv.so}"
STAND_XORG_WRAPPER="${CURSKILL_XORG:-/usr/local/sbin/curskill-xorg}"

STAND_XSERVER=""
STAND_XSERVER_PID=""

stand_have_xorg_root() {
  if [ -x "$STAND_XORG_WRAPPER" ] && sudo -n -l -- "$STAND_XORG_WRAPPER" >/dev/null 2>&1; then
    return 0
  fi
  sudo -n true 2>/dev/null
}

stand_pick_xserver() {
  case "$STAND_X" in
    xvfb) echo xvfb; return ;;
    xorg|auto) ;;
    *) echo "CURSOR_STAND_X=$STAND_X: жду auto|xorg|xvfb" >&2; exit 1 ;;
  esac
  local why=""
  [ -f "$STAND_NVIDIA_DRV" ] || why="нет драйвера $STAND_NVIDIA_DRV"
  [ -n "$why" ] || [ -f "$STAND_XORG_CONF" ] || why="нет конфига $STAND_XORG_CONF"
  [ -n "$why" ] || command -v Xorg >/dev/null || why="нет Xorg"
  [ -n "$why" ] || stand_have_xorg_root || why="нет NOPASSWD на Xorg стенда (curskill-xorg или sudo -n)"
  if [ -n "$why" ]; then
    if [ "$STAND_X" = "xorg" ]; then echo "Xorg на видеокарте невозможен: $why" >&2; exit 1; fi
    echo "ВНИМАНИЕ: $why — поднимаю Xvfb (программный рендер, ~0,6 ядра на стенд)" >&2
    echo xvfb; return
  fi
  echo xorg-nvidia
}

# Монитор на пустой карте. Xorg без выхода отвечает «Monitors: 0» при живых
# 1920×1080. Electron и Telegram сверяют меню с монитором. Xvfb объявляет сам.
stand_declare_monitor() {
  local disp="$1" geo
  if DISPLAY="$disp" xrandr --listmonitors 2>/dev/null | grep -q '^Monitors: 0'; then
    geo=$(DISPLAY="$disp" xdpyinfo 2>/dev/null | awk '/dimensions:/{print $2; exit}')
    DISPLAY="$disp" xrandr --setmonitor STAND "${geo%x*}/508x${geo#*x}/286+0+0" none \
      >/dev/null 2>&1 || true
  fi
  if DISPLAY="$disp" xrandr --listmonitors 2>/dev/null | grep -q '^Monitors: 0'; then
    echo "ВНИМАНИЕ: у экрана $disp нет монитора — раскладка окон может поехать" >&2
  fi
}

stand_start_xserver() {
  local disp="$1" tag="$2" num="${1#:}"
  rm -f "/tmp/.X${num}-lock" "/tmp/.X11-unix/X${num}" 2>/dev/null || true
  STAND_XSERVER=$(stand_pick_xserver)
  if [ "$STAND_XSERVER" = "xorg-nvidia" ]; then
    mkdir -p /tmp/xorg-empty-confdir
    if [ -x "$STAND_XORG_WRAPPER" ]; then
      sudo -n "$STAND_XORG_WRAPPER" start "$disp" "$tag" \
        >"/tmp/xorg-$tag.out" 2>&1 &
    else
      sudo -n Xorg "$disp" -config "$STAND_XORG_CONF" -configdir /tmp/xorg-empty-confdir \
        -sharevts -novtswitch -noreset -nolisten tcp \
        -logfile "/tmp/xorg-$tag.log" >"/tmp/xorg-$tag.out" 2>&1 &
    fi
    STAND_XSERVER_PID=$!; disown; sleep 4
    xdpyinfo -display "$disp" >/dev/null 2>&1 || {
      echo "Xorg на $disp не поднялся:" >&2; tail -5 "/tmp/xorg-$tag.out" >&2
      sudo -n tail -5 "/tmp/xorg-$tag.log" >&2 2>/dev/null || true
      # Хвост журнала часто про занятую карту. Первая причина — модуль ядра
      # старее библиотек после обновления драйвера без перезагрузки.
      if sudo -n grep -q "Failed to initialize the NVIDIA kernel module" \
          "/tmp/xorg-$tag.log" 2>/dev/null; then
        echo "ПРИЧИНА: драйвер видеокарты не завёлся — библиотеки и модуль ядра разных версий" >&2
        echo "  (обновление драйвера без перезагрузки; проверь: nvidia-smi). Лечит перезагрузка;" >&2
        echo "  до неё — программный экран: CURSOR_STAND_X=xvfb" >&2
      fi
      exit 1; }
    stand_declare_monitor "$disp"
  else
    Xvfb "$disp" -screen 0 1920x1080x24 >"/tmp/xvfb-$tag.log" 2>&1 &
    STAND_XSERVER_PID=$!; disown; sleep 2
    xdpyinfo -display "$disp" >/dev/null 2>&1 || {
      echo "Xvfb на $disp не поднялся:" >&2; tail -5 "/tmp/xvfb-$tag.log" >&2; exit 1; }
  fi
  STAND_XSERVER_PID=$(stand_xserver_pid "$disp" "$STAND_XSERVER_PID")
}

stand_xserver_pid() {
  local disp="$1" fallback="${2:-}" num="${1#:}" from_lock=""
  from_lock=$(tr -d ' \n' < "/tmp/.X${num}-lock" 2>/dev/null || true)
  case "$from_lock" in
    ''|*[!0-9]*) echo "$fallback" ;;
    *) echo "$from_lock" ;;
  esac
}

stand_stop_xserver() {
  local disp="$1" xserver="${2:-}" pid="${3:-}"
  pid=$(stand_xserver_pid "$disp" "$pid")
  if [ -z "$pid" ]; then
    echo "PID экрана не нашёлся ни в замке /tmp/.X${disp#:}-lock, ни в состоянии —" >&2
    echo "найди его сам: pgrep -af 'X(org|vfb) $disp' и убей ИМЕННО его." >&2; exit 1
  fi
  local cmd
  cmd=$(ps -o args= -p "$pid" 2>/dev/null || true)
  case "$cmd" in
    "") ;;
    *"$disp "*|*"$disp")
      if [ "$xserver" = "xorg-nvidia" ]; then
        if [ -x "$STAND_XORG_WRAPPER" ]; then
          sudo -n "$STAND_XORG_WRAPPER" stop "$disp"
        else
          sudo -n kill "$pid"
        fi
      else
        kill "$pid"
      fi
      sleep 2 ;;
    *) echo "PID $pid — это не экран $disp ($cmd). Не трогаю." >&2; exit 1 ;;
  esac
  if xdpyinfo -display "$disp" >/dev/null 2>&1; then
    echo "Экран $disp ПРОДОЛЖАЕТ работать после остановки pid $pid." >&2
    echo "Кто на нём: $(pgrep -af "X(org|vfb) $disp" | head -3 | tr '\n' ';')" >&2
    exit 1
  fi
  sudo -n rm -f "/tmp/.X${disp#:}-lock" 2>/dev/null || rm -f "/tmp/.X${disp#:}-lock" 2>/dev/null || true
  echo "Экран $disp (${xserver:-?}, pid $pid) остановлен."
}
