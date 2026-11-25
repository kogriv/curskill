#!/usr/bin/env bash
# Общий резолв путей skill → automation/. Source, не exec.
# shellcheck disable=SC2034

_cursor_stand_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CURSOR_STAND_SKILL="$(cd "$_cursor_stand_scripts/.." && pwd)"
_cursor_stand_root="$(cd "$_cursor_stand_scripts/../.." && pwd)"
_cursor_stand_cfg="${CURSOR_STAND_CONFIG:-$_cursor_stand_root/config/hosts/$(hostname).env}"
if [ -f "$_cursor_stand_cfg" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$_cursor_stand_cfg"
  set +a
fi

cursor_stand_repo_root() {
  # skill/scripts → корень репо cursor-stand (skill/ + automation/).
  cd "$_cursor_stand_scripts/../.." && pwd
}

cursor_stand_resolve_sh() {
  local root c
  if [ -n "${CURSOR_STAND_SH:-}" ]; then
    [ -x "$CURSOR_STAND_SH" ] || return 127
    printf '%s\n' "$CURSOR_STAND_SH"
    return 0
  fi
  root="$(cursor_stand_repo_root)"
  for c in \
    "$root/automation/cursor-stand.sh"
  do
    if [ -x "$c" ]; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 127
}

cursor_stand_resolve_glass() {
  local sh dir
  if [ -n "${CURSOR_STAND_GLASS_AGENTS:-}" ] && [ -f "$CURSOR_STAND_GLASS_AGENTS" ]; then
    printf '%s\n' "$CURSOR_STAND_GLASS_AGENTS"
    return 0
  fi
  sh="$(cursor_stand_resolve_sh)" || return 127
  dir="$(cd "$(dirname "$sh")" && pwd)"
  if [ -f "$dir/glass_agents.py" ]; then
    printf '%s\n' "$dir/glass_agents.py"
    return 0
  fi
  return 127
}

cursor_stand_resolve_display_sh() {
  local root sh dir
  if [ -n "${CURSOR_STAND_DISPLAY_SH:-}" ]; then
    printf '%s\n' "$CURSOR_STAND_DISPLAY_SH"
    return 0
  fi
  sh="$(cursor_stand_resolve_sh 2>/dev/null)" || true
  if [ -n "${sh:-}" ]; then
    dir="$(cd "$(dirname "$sh")" && pwd)"
    if [ -f "$dir/display/stand-display.sh" ]; then
      printf '%s\n' "$dir/display/stand-display.sh"
      return 0
    fi
  fi
  root="$(cursor_stand_repo_root)"
  if [ -f "$root/automation/display/stand-display.sh" ]; then
    printf '%s\n' "$root/automation/display/stand-display.sh"
    return 0
  fi
  return 127
}

cursor_stand_has_cmd() {
  local sh=$1 cmd=$2
  grep -q "cmd_${cmd//-/_}\| $cmd)" "$sh" 2>/dev/null \
    || "$sh" help 2>/dev/null | grep -qw "$cmd"
}

cursor_stand_profile() {
  printf '%s\n' "${CURSOR_STAND_PROFILE:-${XDG_DATA_HOME:-$HOME/.local/share}/cursor-stand}"
}

# Мажор.минор пакета Cursor. Пусто, если не прочитали.
cursor_stand_pkg_ver() {
  local v
  v=$(dpkg-query -W -f='${Version}' cursor 2>/dev/null | cut -d- -f1 || true)
  if [ -z "$v" ] && [ -f /usr/share/cursor/resources/app/package.json ]; then
    v=$(python3 -c 'import json; print(json.load(open("/usr/share/cursor/resources/app/package.json")).get("version") or "")' 2>/dev/null || true)
  fi
  printf '%s\n' "$v"
}

# 3.23.23 → 3.23, 3.21 → 3.21
cursor_stand_ver_mm() {
  printf '%s\n' "$1" | awk -F. '{print $1"."$2}'
}

cursor_stand_ui_calibrated() {
  local sh cal
  cal="${CURSOR_STAND_UI_CALIBRATED:-}"
  if [ -z "$cal" ]; then
    sh="$(cursor_stand_resolve_sh 2>/dev/null)" || true
    if [ -n "${sh:-}" ]; then
      cal=$(sed -n 's/^UI_CALIBRATED="${CURSOR_STAND_UI_CALIBRATED:-\(.*\)}"/\1/p' "$sh" | head -1)
    fi
  fi
  printf '%s\n' "${cal:-3.23}"
}
