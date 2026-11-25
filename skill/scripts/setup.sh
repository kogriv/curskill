#!/usr/bin/env bash
# Проверка машины перед файлом хоста. Пакеты не ставит, экран не поднимает,
# по glass не кликает, файл хоста не пишет.
set -euo pipefail
# shellcheck source=lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1" >&2; fail=1; }
warn() { printf 'warn %s\n' "$1"; }

pkg_of() {
  case "$1" in
    xdotool) printf '%s\n' xdotool ;;
    xclip) printf '%s\n' xclip ;;
    python3) printf '%s\n' python3 ;;
    tesseract) printf '%s\n' 'tesseract-ocr tesseract-ocr-eng' ;;
    Xorg) printf '%s\n' xserver-xorg-core ;;
    xdpyinfo) printf '%s\n' x11-utils ;;
    xrandr) printf '%s\n' x11-xserver-utils ;;
    Xvfb) printf '%s\n' xvfb ;;
    openbox) printf '%s\n' openbox ;;
    x11vnc) printf '%s\n' x11vnc ;;
    import) printf '%s\n' imagemagick ;;
    scrot) printf '%s\n' scrot ;;
    *) printf '%s\n' "$1" ;;
  esac
}

echo "setup: хост $(hostname)  user $(id -un)"
echo "setup: пакеты не ставятся, стенд не поднимается. Дальше — SETUP.md"

need() {
  local bin=$1
  if command -v "$bin" >/dev/null 2>&1; then
    ok "$bin"
  else
    bad "нет $bin — пакет Debian/Ubuntu: $(pkg_of "$bin")"
  fi
}

for bin in xdotool xclip python3 tesseract Xorg xdpyinfo; do
  need "$bin"
done

if command -v import >/dev/null 2>&1 || command -v scrot >/dev/null 2>&1; then
  ok "снимок ($(command -v import 2>/dev/null || true) $(command -v scrot 2>/dev/null || true))"
else
  bad "нет import и scrot — пакет imagemagick или scrot"
fi

if python3 -c 'from PIL import Image' 2>/dev/null; then
  ok "Pillow"
else
  bad "нет Pillow — пакет python3-pil"
fi

if tesseract --list-langs 2>/dev/null | grep -qx eng; then
  ok "tesseract eng"
else
  bad "нет языка eng — пакет tesseract-ocr-eng"
fi
if tesseract --list-langs 2>/dev/null | grep -qx rus; then
  ok "tesseract rus"
else
  warn "нет языка rus — имя сессии лучше давать через --id (tesseract-ocr-rus)"
fi

for bin in Xvfb openbox x11vnc xrandr; do
  if command -v "$bin" >/dev/null 2>&1; then
    ok "$bin"
  else
    warn "нет $bin — пакет $(pkg_of "$bin")"
  fi
done

drv="${CURSOR_STAND_NVIDIA_DRV:-/usr/lib/x86_64-linux-gnu/nvidia/xorg/nvidia_drv.so}"
wrap="${CURSKILL_XORG:-/usr/local/sbin/curskill-xorg}"
gpu=0
if [ -f "$drv" ]; then
  ok "nvidia $drv"
  gpu=1
else
  warn "нет $drv — CURSOR_STAND_X=xvfb"
fi
if [ -x "$wrap" ] && sudo -n -l -- "$wrap" >/dev/null 2>&1; then
  ok "NOPASSWD $wrap"
  gpu=$((gpu + 1))
elif sudo -n true >/dev/null 2>&1; then
  ok "sudo -n true"
  gpu=$((gpu + 1))
else
  warn "нет passwordless sudo — CURSOR_STAND_X=xvfb, обёртку Xorg не ставить молча"
fi

disp="${CURSOR_STAND_DISPLAY:-:105}"
if xdpyinfo -display "$disp" >/dev/null 2>&1; then
  warn "DISPLAY $disp уже жив — в файл хоста не писать этот номер вторым экраном, не делать up"
else
  ok "DISPLAY $disp свободен"
fi

vnc="${CURSOR_STAND_VNC:-5916}"
if ss -ltn 2>/dev/null | grep -qE ":${vnc}( |$)"; then
  warn "порт VNC $vnc занят — спросить другой"
else
  ok "порт VNC $vnc свободен"
fi

if [ -x /usr/share/cursor/cursor ] || [ -x /usr/share/cursor/cursor-bin ]; then
  ok "пакет Cursor"
else
  warn "нет /usr/share/cursor/cursor — пакет Cursor ставит человек"
fi

proxy_bin="${CURSOR_STAND_BIN:-/usr/local/bin/cursor-proxy}"
if [ -x "$proxy_bin" ]; then
  ok "$proxy_bin"
else
  warn "нет $proxy_bin — копировать automation/cursor-proxy только после согласия, up без него не стартует"
fi

echo
echo "спросить человека, не угадывать:"
echo "  прокси: URL или «без прокси»"
echo "  у монитора этой видеокарты сейчас кто-нибудь есть"
echo "  поднимать стенд таймером или только руками"
echo "  какие сессии archive не трогает (пока пусто — archive не запускать)"
echo
if [ "$fail" -ne 0 ]; then
  echo "setup: система не готова, файл хоста не заполнять" >&2
  exit 1
fi
echo "setup: обязательные команды есть. Дальше файл хоста и ответы человека."
echo "setup: CURSKILL_SETUP_DONE=1 ставить после ответов, не этой командой."
exit 0
